-- Table: {{SCHEMA}}.{{HIST}}
-- Historik för {{SCHEMA}}.{{TABLE}}: gamla versionen av raden sparas vid UPDATE och DELETE.

CREATE TABLE IF NOT EXISTS {{SCHEMA_Q}}.{{HIST_Q}}
(
    historik_id bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
    andringstyp character varying(10) COLLATE pg_catalog."default" NOT NULL,
    andrad_datum timestamp without time zone NOT NULL DEFAULT now(),
    andrad_av character varying(50) COLLATE pg_catalog."default" NOT NULL DEFAULT current_user,
{{HIST_COLUMNS}},
    CONSTRAINT {{HIST_PKEY_Q}} PRIMARY KEY (historik_id),
    CONSTRAINT {{HIST_CHECK_Q}} CHECK (andringstyp IN ('UPDATE', 'DELETE'))
)
TABLESPACE pg_default;

ALTER TABLE IF EXISTS {{SCHEMA_Q}}.{{HIST_Q}}
    OWNER to geodataowner;

REVOKE ALL ON TABLE {{SCHEMA_Q}}.{{HIST_Q}} FROM geoserver_r;
REVOKE ALL ON TABLE {{SCHEMA_Q}}.{{HIST_Q}} FROM geoserver_w;
REVOKE ALL ON TABLE {{SCHEMA_Q}}.{{HIST_Q}} FROM qgis_r;

-- Skrivande roller får bara lägga till rader (via triggern), inte ändra eller ta bort historik
GRANT ALL ON TABLE {{SCHEMA_Q}}.{{HIST_Q}} TO geodataowner;
GRANT SELECT ON TABLE {{SCHEMA_Q}}.{{HIST_Q}} TO geoserver;
GRANT SELECT ON TABLE {{SCHEMA_Q}}.{{HIST_Q}} TO geoserver_r;
GRANT INSERT, SELECT ON TABLE {{SCHEMA_Q}}.{{HIST_Q}} TO geoserver_w;
GRANT ALL ON TABLE {{SCHEMA_Q}}.{{HIST_Q}} TO joh17bla;
GRANT SELECT ON TABLE {{SCHEMA_Q}}.{{HIST_Q}} TO qgis_r;

CREATE INDEX IF NOT EXISTS {{HIST_GID_IDX_Q}}
    ON {{SCHEMA_Q}}.{{HIST_Q}} USING btree
    (gid, andrad_datum)
    TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS {{HIST_GEOM_IDX_Q}}
    ON {{SCHEMA_Q}}.{{HIST_Q}} USING gist
    (geom)
    TABLESPACE pg_default;

-- Triggerfunktion: sparar OLD-raden i historiktabellen
CREATE OR REPLACE FUNCTION {{SCHEMA_Q}}.{{FN_SAVE_Q}}()
RETURNS trigger
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
  INSERT INTO {{SCHEMA_Q}}.{{HIST_Q}} (andringstyp, {{COL_LIST}})
  VALUES (TG_OP, {{OLD_COL_LIST}});
  RETURN NULL;
END;
$BODY$;

ALTER FUNCTION {{SCHEMA_Q}}.{{FN_SAVE_Q}}() OWNER TO geodataowner;

-- Trigger: trigger_spara_historik
DROP TRIGGER IF EXISTS "trigger_spara_historik" ON {{SCHEMA_Q}}.{{TABLE_Q}};
CREATE TRIGGER "trigger_spara_historik"
    AFTER UPDATE OR DELETE
    ON {{SCHEMA_Q}}.{{TABLE_Q}}
    FOR EACH ROW
    EXECUTE FUNCTION {{SCHEMA_Q}}.{{FN_SAVE_Q}}();

-- Återställ en rad till versionen i en viss historikrad:
--   SELECT {{SCHEMA_Q}}.{{FN_RESTORE_Q}}(<historik_id>);
-- Finns raden kvar uppdateras den, annars läggs den tillbaka med samma gid.
-- Själva återställningen loggas i sin tur i historiken (som UPDATE).
CREATE OR REPLACE FUNCTION {{SCHEMA_Q}}.{{FN_RESTORE_Q}}(p_historik_id bigint)
RETURNS void
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
  h {{SCHEMA_Q}}.{{HIST_Q}}%ROWTYPE;
BEGIN
  SELECT * INTO h FROM {{SCHEMA_Q}}.{{HIST_Q}} WHERE historik_id = p_historik_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Historikrad % finns inte i {{SCHEMA}}.{{HIST}}', p_historik_id;
  END IF;

  IF EXISTS (SELECT 1 FROM {{SCHEMA_Q}}.{{TABLE_Q}} t WHERE t.gid = h.gid) THEN
    UPDATE {{SCHEMA_Q}}.{{TABLE_Q}}
           SET {{SET_LIST}}
     WHERE gid = h.gid;
  ELSE
    INSERT INTO {{SCHEMA_Q}}.{{TABLE_Q}} ({{COL_LIST}})
    OVERRIDING SYSTEM VALUE
    VALUES ({{H_COL_LIST}});
  END IF;
END;
$BODY$;

ALTER FUNCTION {{SCHEMA_Q}}.{{FN_RESTORE_Q}}(bigint) OWNER TO geodataowner;
