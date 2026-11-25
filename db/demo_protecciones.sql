-- Protecciones de la demo pública (se aplican al reconstruir la base).
-- 1) Topes de registros: nadie puede llenar la base aunque repita operaciones.
CREATE OR REPLACE FUNCTION core.tope_demo() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
  EXECUTE format('SELECT count(*) FROM %I.%I', TG_TABLE_SCHEMA, TG_TABLE_NAME) INTO n;
  IF n >= TG_ARGV[0]::bigint THEN
    RAISE EXCEPTION 'La demo alcanzó su límite de registros por hoy; se restaura automáticamente cada día.';
  END IF;
  RETURN NEW;
END $$;
DO $$
DECLARE t record;
BEGIN
  FOR t IN SELECT * FROM (VALUES ('liq','liquidacion',3000), ('liq','liquidacion_linea',60000), ('cs','carga',600),
                                 ('cs','evento',5000), ('ops','importacion',100), ('ops','importacion_fila',20000)) v(esq, tab, tope)
  LOOP
    EXECUTE format('CREATE TRIGGER tope_demo BEFORE INSERT ON %I.%I FOR EACH ROW EXECUTE FUNCTION core.tope_demo(%s)', t.esq, t.tab, t.tope);
  END LOOP;
END $$;

-- 2) Textos acotados en lo que escribe un visitante
ALTER TABLE cs.carga ADD CONSTRAINT demo_textos CHECK (length(bl) <= 40 AND coalesce(length(nave),0) <= 60 AND coalesce(length(orden_servicio),0) <= 30
  AND coalesce(length(ubicacion),0) <= 60 AND coalesce(length(observacion),0) <= 300 AND coalesce(length(detalle_salida),0) <= 300);
ALTER TABLE liq.liquidacion ADD CONSTRAINT demo_textos CHECK (coalesce(length(emitido_por),0) <= 80 AND coalesce(length(factura_numero),0) <= 30
  AND coalesce(length(anulado_motivo),0) <= 300);

-- 3) Usuario de la aplicación sin permisos sobre la estructura (no puede borrar ni alterar tablas)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_demo') THEN
    GRANT USAGE ON SCHEMA core, dt, ops, tarifas, liq, cs TO app_demo;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core, dt, ops, tarifas, liq, cs TO app_demo;
    GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA core, dt, ops, tarifas, liq, cs TO app_demo;
    GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core, dt, ops, tarifas, liq, cs TO app_demo;
    -- Lo que define el negocio (tarifas, clientes, data del depósito) es de solo lectura para la app
    REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tarifas, core FROM app_demo;
    REVOKE INSERT, UPDATE, DELETE ON dt.contenedor, ops.movilizacion, ops.servicio_adicional FROM app_demo;
  END IF;
END $$;
