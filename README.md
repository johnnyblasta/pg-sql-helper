# pg-sql-helper

Webbverktyg som genererar färdig SQL för PostgreSQL/PostGIS: schema, geodatatabeller, behörigheter, index, triggers och valfri historiktabell. Fyll i ett formulär i webbläsaren, generera SQL och kopiera den eller ladda ner den som `.sql`-fil för att köra i t.ex. pgAdmin eller `psql`.

Verktyget kör ingen SQL själv och ansluter inte till någon databas.

## Innehåll

- [Kom igång](#kom-igång)
- [Användning](#användning)
- [Vad som genereras](#vad-som-genereras)
- [Historiktabell](#historiktabell)
- [Förutsättningar i databasen](#förutsättningar-i-databasen)
- [API](#api)
- [Projektstruktur](#projektstruktur)
- [Anpassa](#anpassa)

## Kom igång

### Lokalt med Node.js

Kräver Node.js 20 eller senare.

```bash
npm ci
npm start
```

Öppna sedan http://localhost:3000.

### Med Docker

```bash
docker build -t pg-sql-helper .
docker run -p 3000:3000 pg-sql-helper
```

Öppna sedan http://localhost:3000.

## Användning

1. Ange **schemanamn**.
2. För varje tabell (lägg till fler med **+ Lägg till tabell**):
   - **Tabellnamn**
   - **Geom: typ**: `Geometry`, `Point`, `LineString`, `Polygon`, `MultiPoint`, `MultiLineString` eller `MultiPolygon`
   - **Geom: SRID**: 3006 (SWEREF 99 TM), 3013 eller 3014
   - **Frivilliga fält** att ta med
   - **Triggers** att koppla på. Kolumner som en trigger behöver bockas i automatiskt.
   - **Skapa historiktabell** om ändringar ska loggas (se [Historiktabell](#historiktabell))
3. Klicka **Generera SQL** för att visa resultatet, eller **Ladda ner .sql** för att spara det som `<schemanamn>.sql`.

Schema- och tabellnamn måste matcha `^[a-zA-Z_][a-zA-Z0-9_]{0,62}$` (börja med bokstav eller `_`, max 63 tecken). Med historiktabell blir tabellnamnet i praktiken kortare, eftersom även `<tabell>_spara_historik` måste rymmas inom 63 tecken.

## Vad som genereras

### Schema

- `CREATE SCHEMA IF NOT EXISTS` med ägare `geodataowner`
- `USAGE` på schemat till `PUBLIC`, `geoserver`, `geoserver_r` och `qgis_r`
- Standardbehörigheter (`ALTER DEFAULT PRIVILEGES`) för nya tabeller
- Triggerfunktionerna nedan, skapade i schemat

### Tabeller

Varje tabell får följande:

| Kolumn | Typ | |
|---|---|---|
| `gid` | `integer`, identity | Primärnyckel, alltid med |
| `geom` | `geometry(<typ>,<srid>)` | Alltid med, med GIST-index |
| `skapad_av` | `varchar(50)` | Alltid med |
| `skapad_datum` | `timestamp` | Alltid med |
| `modifierad_av` | `varchar(50)` | Alltid med |
| `modifierad_datum` | `timestamp` | Alltid med |
| `namn` | `varchar(50)` | Frivillig |
| `typ` | `varchar(50)` | Frivillig |
| `lagesosakerhet_plan` | `numeric(10,5)` | Frivillig |
| `insamlingsmetod` | `varchar(50)` | Frivillig |
| `langd` | `double precision` | Frivillig |
| `area` | `numeric(10,2)` | Frivillig |

Behörigheter per tabell:

| Roll | Behörighet |
|---|---|
| `geodataowner` | ägare, ALL |
| `geoserver` | ALL |
| `geoserver_w` | SELECT, INSERT, UPDATE, DELETE |
| `geoserver_r`, `qgis_r` | SELECT |
| `joh17bla` | ALL |

### Triggers

| Trigger | När | Gör |
|---|---|---|
| `trigger_uppdatera_skapad_av` | BEFORE INSERT | `skapad_av := current_user` |
| `trigger_uppdatera_skapad_datum` | BEFORE INSERT | `skapad_datum := now()` |
| `trigger_uppdatera_modifierad_av` | BEFORE INSERT OR UPDATE | `modifierad_av := current_user` |
| `trigger_uppdatera_modifierad_datum` | BEFORE INSERT OR UPDATE | `modifierad_datum := now()` |
| `trigger_uppdatera_langd` | BEFORE INSERT OR UPDATE | `langd := ST_Length(geom)`, avrundat till 2 decimaler |
| `trigger_uppdatera_area` | BEFORE INSERT OR UPDATE | `area := ST_Area(geom)`, avrundat till 2 decimaler |

## Historiktabell

När **Skapa historiktabell** är ikryssad skapas tre saker utöver själva tabellen.

### 1. Tabellen `<tabell>_historik`

Den har samma kolumner som huvudtabellen plus:

| Kolumn | Innehåll |
|---|---|
| `historik_id` | Primärnyckel, räknas upp automatiskt |
| `andringstyp` | `'UPDATE'` eller `'DELETE'` |
| `andrad_datum` | Tidpunkt för ändringen (`now()`) |
| `andrad_av` | Vem som gjorde ändringen (`current_user`) |

`gid` är här en vanlig kolumn (inte primärnyckel), eftersom samma objekt kan ha många historikrader. Tabellen får index på `(gid, andrad_datum)` och ett GIST-index på `geom`.

`geoserver_w` får bara INSERT och SELECT, så skrivande användare kan inte ändra eller radera historik. Läsrollerna får SELECT.

### 2. Triggern `trigger_spara_historik`

Körs `AFTER UPDATE OR DELETE` på huvudtabellen och sparar raden **som den såg ut före ändringen**. INSERT loggas inte, eftersom den första versionen finns i huvudtabellen tills den ändras.

### 3. Funktionen `<tabell>_aterstall(historik_id)`

Återställer ett objekt till versionen i en viss historikrad:

- Finns raden kvar uppdateras den till den gamla versionen.
- Är raden borttagen läggs den tillbaka med samma `gid`.
- Själva återställningen loggas i sin tur i historiken, så den går också att ångra.

Om triggrarna för `skapad_*` och `modifierad_*` är valda sätter de sina värden som vanligt vid återställning. En borttagen rad som läggs tillbaka får alltså nya värden i `skapad_av` och `skapad_datum`.

### Exempel

```sql
-- Visa ändringshistorik för ett objekt, senaste först
SELECT historik_id, andringstyp, andrad_datum, andrad_av, namn
FROM mitt_schema.objekt_historik
WHERE gid = 42
ORDER BY andrad_datum DESC;

-- Visa borttagna objekt
SELECT * FROM mitt_schema.objekt_historik
WHERE andringstyp = 'DELETE'
ORDER BY andrad_datum DESC;

-- Återställ till versionen i historikrad 123
SELECT mitt_schema.objekt_aterstall(123);
```

## Förutsättningar i databasen

Den genererade SQL:en förutsätter att följande redan finns:

- PostGIS-tillägget (`CREATE EXTENSION postgis;`)
- Rollerna `geodataowner`, `geoserver`, `geoserver_r`, `geoserver_w`, `qgis_r` och `joh17bla`

Skripten använder `IF NOT EXISTS`, `CREATE OR REPLACE` och `DROP TRIGGER IF EXISTS`, så de går att köra flera gånger. En tabell som redan finns ändras dock inte; nya kolumner läggs inte till i befintliga tabeller.

## API

Formuläret anropar ett enda endpoint, som också kan användas direkt.

`POST /api/generate-sql`

```json
{
  "schemaName": "mitt_schema",
  "tables": [
    {
      "name": "objekt",
      "geomType": "Point",
      "srid": 3006,
      "mandatoryFields": ["gid", "geom", "skapad_av", "skapad_datum", "modifierad_av", "modifierad_datum"],
      "optionalFields": ["namn", "typ"],
      "triggers": ["uppdatera_skapad_av", "uppdatera_skapad_datum", "uppdatera_modifierad_av", "uppdatera_modifierad_datum"],
      "historik": true
    }
  ]
}
```

Svar: `{ "sql": "..." }`, eller `{ "error": "..." }` med status 400 vid ogiltig indata.

## Projektstruktur

| Fil | Innehåll |
|---|---|
| `server.js` | Express-server, validering och SQL-generering |
| `index.html` | Formuläret som visas på `/` |
| `template-base.sql` | Mall för schema, behörigheter och triggerfunktioner |
| `template-table.sql` | Mall för en tabell med behörigheter och index |
| `template-historik.sql` | Mall för historiktabell, historiktrigger och återställningsfunktion |
| `Dockerfile` | Bygger en produktionsimage baserad på `node:20-alpine` |

`table.html` och `template.sql` är äldre versioner som inte används av servern.

## Anpassa

- **Nya kolumner**: lägg till i `COLUMN_DEFS` i `server.js` och i `OPTIONAL_FIELDS` i `index.html`.
- **Fler SRID**: lägg till i `ALLOWED_SRIDS` i `server.js` och i `SRIDS` i `index.html`.
- **Nya triggers**: lägg till funktionen i `template-base.sql`, en post i `TRIGGERS` i `server.js` och en i `TRIGGERS` i `index.html` (nycklarna måste vara samma).
- **Roller och behörigheter**: ändra i `template-base.sql`, `template-table.sql` och `template-historik.sql`.

## Licens

GPL-3.0, se [LICENSE](LICENSE).
