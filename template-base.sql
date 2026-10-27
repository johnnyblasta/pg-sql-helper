CREATE SCHEMA IF NOT EXISTS {{SCHEMA_Q}}
    AUTHORIZATION geodataowner;

GRANT USAGE ON SCHEMA {{SCHEMA_Q}} TO PUBLIC;
GRANT ALL ON SCHEMA {{SCHEMA_Q}} TO geodataowner;
GRANT USAGE ON SCHEMA {{SCHEMA_Q}} TO geoserver_r;
GRANT USAGE ON SCHEMA {{SCHEMA_Q}} TO geoserver_w;
GRANT USAGE ON SCHEMA {{SCHEMA_Q}} TO qgis_r;

ALTER DEFAULT PRIVILEGES FOR ROLE geodataowner IN SCHEMA {{SCHEMA_Q}}
GRANT SELECT ON TABLES TO geoserver_r;

ALTER DEFAULT PRIVILEGES FOR ROLE geodataowner IN SCHEMA {{SCHEMA_Q}}
GRANT SELECT ON TABLES TO qgis_r;

ALTER DEFAULT PRIVILEGES FOR ROLE joh17bla IN SCHEMA {{SCHEMA_Q}}
GRANT ALL ON TABLES TO geodataowner;

CREATE OR REPLACE FUNCTION {{SCHEMA_Q}}.uppdatera_area()
RETURNS trigger
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    NEW.area := round(ST_Area(NEW.geom)::numeric, 2);
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION {{SCHEMA_Q}}.uppdatera_area() OWNER TO geodataowner;

CREATE OR REPLACE FUNCTION {{SCHEMA_Q}}.uppdatera_langd()
RETURNS trigger
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
    NEW.langd := round(ST_Length(NEW.geom)::numeric, 2);
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION {{SCHEMA_Q}}.uppdatera_langd() OWNER TO geodataowner;

CREATE OR REPLACE FUNCTION {{SCHEMA_Q}}.uppdatera_modifierad_av()
RETURNS trigger
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
  NEW.modifierad_av := current_user;
  RETURN NEW;
END;
$BODY$;

ALTER FUNCTION {{SCHEMA_Q}}.uppdatera_modifierad_av() OWNER TO geodataowner;

CREATE OR REPLACE FUNCTION {{SCHEMA_Q}}.uppdatera_modifierad_datum()
RETURNS trigger
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
  NEW.modifierad_datum := now();
  RETURN NEW;
END;
$BODY$;

ALTER FUNCTION {{SCHEMA_Q}}.uppdatera_modifierad_datum() OWNER TO geodataowner;

CREATE OR REPLACE FUNCTION {{SCHEMA_Q}}.uppdatera_skapad_av()
RETURNS trigger
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
  NEW.skapad_av := current_user;
  RETURN NEW;
END;
$BODY$;

ALTER FUNCTION {{SCHEMA_Q}}.uppdatera_skapad_av() OWNER TO geodataowner;

CREATE OR REPLACE FUNCTION {{SCHEMA_Q}}.uppdatera_skapad_datum()
RETURNS trigger
LANGUAGE 'plpgsql'
AS $BODY$
BEGIN
  NEW.skapad_datum := now();
  RETURN NEW;
END;
$BODY$;

ALTER FUNCTION {{SCHEMA_Q}}.uppdatera_skapad_datum() OWNER TO geodataowner;