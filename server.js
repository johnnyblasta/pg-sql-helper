import express from "express";
import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";

const app = express();
app.use(express.json());

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function validateIdent(name, label = "Namn") {
  if (typeof name !== "string") return `${label} är ogiltigt`;
  const n = name.trim();
  if (!/^[a-zA-Z_][a-zA-Z0-9_]{0,62}$/.test(n)) {
    return `${label} måste matcha: ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ (max 63 tecken)`;
  }
  return null;
}
function quoteIdent(ident) {
  return `"${ident.replaceAll('"', '""')}"`;
}
const uniq = (a) => [...new Set(a)];
function applyTemplate(template, vars) {
  let out = template;
  for (const [k, v] of Object.entries(vars)) out = out.replaceAll(`{{${k}}}`, v);
  return out;
}

// Tillåtna SRID (lägg till fler om ni vill)
const ALLOWED_SRIDS = new Set([
  3006, // SWEREF 99 TM
  3013, 
  3014, 
]);

// Tillåtna geometri-typer (PostGIS)
const ALLOWED_GEOM_TYPES = new Set([
  "Geometry",
  "Point",
  "LineString",
  "Polygon",
  "MultiPoint",
  "MultiLineString",
  "MultiPolygon",
]);

// Bas-kolumner (geom renderas separat pga typ+srid)
const COLUMN_DEFS = {
  gid: `    gid integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 )`,
  namn: `    namn character varying(50) COLLATE pg_catalog."default"`,
  typ: `    typ character varying(50) COLLATE pg_catalog."default"`,
  lagesosakerhet_plan: `    lagesosakerhet_plan numeric(10,5)`,
  insamlingsmetod: `    insamlingsmetod character varying(50) COLLATE pg_catalog."default"`,

  skapad_av: `    skapad_av character varying(50) COLLATE pg_catalog."default"`,
  skapad_datum: `    skapad_datum timestamp without time zone`,
  modifierad_av: `    modifierad_av character varying(50) COLLATE pg_catalog."default"`,
  modifierad_datum: `    modifierad_datum timestamp without time zone`,

  langd: `    langd double precision`,
  area: `    area numeric(10,2)`,
};

const TRIGGERS = {
  uppdatera_langd: {
    trigName: "trigger_uppdatera_langd",
    timing: "BEFORE INSERT",
    requires: ["langd", "geom"],
    fn: "uppdatera_langd",
  },
  uppdatera_area: {
    trigName: "trigger_uppdatera_area",
    timing: "BEFORE INSERT",
    requires: ["area", "geom"],
    fn: "uppdatera_area",
  },
  uppdatera_modifierad_av: {
    trigName: "trigger_uppdatera_modifierad_av",
    timing: "BEFORE INSERT OR UPDATE",
    requires: ["modifierad_av"],
    fn: "uppdatera_modifierad_av",
  },
  uppdatera_modifierad_datum: {
    trigName: "trigger_uppdatera_modifierad_datum",
    timing: "BEFORE INSERT OR UPDATE",
    requires: ["modifierad_datum"],
    fn: "uppdatera_modifierad_datum",
  },
  uppdatera_skapad_av: {
    trigName: "trigger_uppdatera_skapad_av",
    timing: "BEFORE INSERT",
    requires: ["skapad_av"],
    fn: "uppdatera_skapad_av",
  },
  uppdatera_skapad_datum: {
    trigName: "trigger_uppdatera_skapad_datum",
    timing: "BEFORE INSERT",
    requires: ["skapad_datum"],
    fn: "uppdatera_skapad_datum",
  },
};

function renderGeomColumn({ geomType, srid }) {
  const gt = (geomType || "Geometry").trim();
  const sr = Number(srid);

  if (!ALLOWED_GEOM_TYPES.has(gt)) {
    throw new Error(`Ogiltig geomType: ${gt}`);
  }
  if (!Number.isInteger(sr) || !ALLOWED_SRIDS.has(sr)) {
    throw new Error(`Ogiltig SRID: ${srid}. Tillåtna: ${[...ALLOWED_SRIDS].join(", ")}`);
  }

  return `    geom geometry(${gt},${sr})`;
}

function renderColumnsSql({ mandatoryFields, optionalFields, geomType, srid, selectedTriggers }) {
  const baseMandatory = ["gid", "geom", "skapad_av", "skapad_datum", "modifierad_av", "modifierad_datum"];

  const mand = uniq([...(mandatoryFields || []), ...baseMandatory]);
  const opt = uniq(optionalFields || []);
  const triggerRequired = uniq((selectedTriggers || []).flatMap(k => TRIGGERS[k]?.requires ?? []));

  const finalCols = uniq([...mand, ...opt, ...triggerRequired]);

  // validera (geom hanteras separat)
  for (const c of finalCols) {
    if (c === "geom") continue;
    if (!COLUMN_DEFS[c]) throw new Error(`Okänt fält: ${c}`);
  }

  // ordning (gid först, metadata, geom, resten)
  const ordered = [];
  const pushIf = (k) => { if (finalCols.includes(k) && !ordered.includes(k)) ordered.push(k); };

  pushIf("gid");
  pushIf("namn"); // om vald
  pushIf("typ");
  pushIf("lagesosakerhet_plan");
  pushIf("insamlingsmetod");

  pushIf("skapad_av");
  pushIf("skapad_datum");
  pushIf("modifierad_av");
  pushIf("modifierad_datum");

  pushIf("geom");
  // resten (t.ex. area/langd)
  for (const c of finalCols) if (!ordered.includes(c)) ordered.push(c);

  const lines = ordered.map(c => {
    if (c === "geom") return renderGeomColumn({ geomType, srid });
    return COLUMN_DEFS[c];
  });

  return lines.join(",\n");
}

function renderGeomIndex({ schemaQ, tableQ, hasGeom }) {
  if (!hasGeom) return `-- (geom ej vald => inget GIST-index)\n`;
  return `
CREATE INDEX IF NOT EXISTS ${tableQ}_geom_idx
    ON ${schemaQ}.${tableQ} USING gist
    (geom)
    TABLESPACE pg_default;
`.trim() + "\n";
}

function renderTriggersSql({ schemaQ, tableQ, selectedTriggerKeys }) {
  const keys = uniq(selectedTriggerKeys || []);
  for (const k of keys) if (!TRIGGERS[k]) throw new Error(`Okänd trigger: ${k}`);

  let sql = "";
  for (const k of keys) {
    const t = TRIGGERS[k];
    const trigNameQ = quoteIdent(t.trigName);

    sql += `
-- Trigger: ${t.trigName}
DROP TRIGGER IF EXISTS ${trigNameQ} ON ${schemaQ}.${tableQ};
CREATE TRIGGER ${trigNameQ}
    ${t.timing}
    ON ${schemaQ}.${tableQ}
    FOR EACH ROW
    EXECUTE FUNCTION ${schemaQ}.${quoteIdent(t.fn)}();
`.trim() + "\n\n";
  }
  return sql.trim() + "\n";
}

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "index.html"));
});

app.post("/api/generate-sql", async (req, res) => {
  try {
    const schemaName = (req.body?.schemaName ?? "").trim();
    const schemaErr = validateIdent(schemaName, "Schemanamn");
    if (schemaErr) return res.status(400).json({ error: schemaErr });

    const schemaQ = quoteIdent(schemaName);

    const baseTemplate = await fs.readFile(path.join(__dirname, "template-base.sql"), "utf8");
    const tableTemplate = await fs.readFile(path.join(__dirname, "template-table.sql"), "utf8");

    const baseSql = applyTemplate(baseTemplate, { SCHEMA: schemaName, SCHEMA_Q: schemaQ });

    const tables = Array.isArray(req.body?.tables) ? req.body.tables : [];
    let tablesSql = "";

    for (const t of tables) {
      const tableName = (t?.name ?? "").trim();
      const tableErr = validateIdent(tableName, "Tabellnamn");
      if (tableErr) throw new Error(tableErr);

      const tableQ = quoteIdent(tableName);

      const selectedTriggers = uniq(t?.triggers || []);

      // geom-inställningar (obligatoriskt)
      const geomType = (t?.geomType ?? "Geometry").trim();
      const srid = t?.srid ?? 3006; // default SWEREF 99 TM

      const columnsSql = renderColumnsSql({
        mandatoryFields: t?.mandatoryFields || [],
        optionalFields: t?.optionalFields || [],
        geomType,
        srid,
        selectedTriggers,
      });

      const hasGeom = true; // geom är obligatoriskt i detta upplägg
      const geomIndexSql = renderGeomIndex({ schemaQ, tableQ, hasGeom });

      const triggersSql = renderTriggersSql({ schemaQ, tableQ, selectedTriggerKeys: selectedTriggers });

      const oneTableSql = applyTemplate(tableTemplate, {
        SCHEMA: schemaName,
        SCHEMA_Q: schemaQ,
        TABLE: tableName,
        TABLE_Q: tableQ,
        COLUMNS: columnsSql,
        GEOM_INDEX: geomIndexSql,
        TRIGGERS: triggersSql,
      });

      tablesSql += "\n\n" + oneTableSql.trim() + "\n";
    }

    res.json({ sql: (baseSql.trim() + "\n\n" + tablesSql.trim() + "\n").trim() + "\n" });
  } catch (e) {
    res.status(400).json({ error: e?.message || "Kunde inte generera SQL" });
  }
});

app.listen(3000, () => console.log("http://localhost:3000"));