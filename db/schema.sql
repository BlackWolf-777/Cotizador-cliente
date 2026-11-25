-- =====================================================================
-- Esquema completo del cotizador (PostgreSQL 15+).
--   core     clientes, agencias y parámetros
--   dt       data del depósito temporal (contenedores) y pendientes
--   ops      importaciones: Control Movilizaciones y Servicios adicionales del puerto
--   tarifas  tarifarios por acuerdo comercial y sus reglas (disparadores)
--   liq      motor de cotización, liquidaciones versionadas y JSON para facturación
--   cs       carga suelta: stock por BL, liquidación mensual y depósito simple
-- Toda la lógica de cobro vive en funciones SQL; la web solo muestra y edita.
-- =====================================================================
--
-- PostgreSQL database dump
--



SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: core; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA core;


--
-- Name: cs; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA cs;


--
-- Name: dt; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA dt;


--
-- Name: liq; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA liq;


--
-- Name: ops; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA ops;


--
-- Name: tarifas; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tarifas;


--
-- Name: iso6346_valido(text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.iso6346_valido(p text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE
  c text := upper(trim(coalesce(p,'')));
  letras constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  valores constant int[] := ARRAY[10,12,13,14,15,16,17,18,19,20,21,23,24,25,26,27,28,29,30,31,32,34,35,36,37,38];
  s int := 0; v int; ch text;
BEGIN
  IF c !~ '^[A-Z]{4}\d{7}$' THEN RETURN false; END IF;
  FOR i IN 1..10 LOOP
    ch := substr(c, i, 1);
    v := CASE WHEN i <= 4 THEN valores[strpos(letras, ch)] ELSE ch::int END;
    s := s + v * (2 ^ (i-1))::int;
  END LOOP;
  RETURN (s % 11) % 10 = substr(c, 11, 1)::int;
END $_$;


--
-- Name: norm(text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.norm(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT NULLIF(regexp_replace(upper(trim(translate(coalesce(p,''),
         'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNAEIOUUN'))), '\s+', ' ', 'g'), '')
$$;


--
-- Name: to_fecha(text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.to_fecha(p text) RETURNS date
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE v text := trim(coalesce(p,''));
BEGIN
  IF v ~ '^\d{4}-\d{2}-\d{2}' THEN RETURN left(v,10)::date; END IF;
  IF v ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN RETURN to_date(v, 'MM/DD/YYYY'); END IF;
  RETURN NULL;
EXCEPTION WHEN others THEN RETURN NULL;
END $_$;


--
-- Name: to_fecha_semana(text, integer); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.to_fecha_semana(p text, p_semana integer) RETURNS date
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE v text := trim(coalesce(p,'')); a int; b int; y int; c1 date; c2 date;
BEGIN
  IF v ~ '^\d{4}-\d{2}-\d{2}' THEN RETURN left(v,10)::date; END IF;
  IF v !~ '^\d{1,2}/\d{1,2}/\d{4}' THEN RETURN NULL; END IF;
  a := split_part(v,'/',1)::int; b := split_part(v,'/',2)::int; y := left(split_part(v,'/',3),4)::int;
  BEGIN c1 := make_date(y, b, a); EXCEPTION WHEN others THEN c1 := NULL; END;  -- día/mes
  BEGIN c2 := make_date(y, a, b); EXCEPTION WHEN others THEN c2 := NULL; END;  -- mes/día
  IF c1 IS NULL OR c2 IS NULL OR c1 = c2 OR p_semana IS NULL THEN RETURN coalesce(c1, c2); END IF;
  RETURN CASE WHEN abs(extract(week FROM c2)::int - p_semana) < abs(extract(week FROM c1)::int - p_semana)
              THEN c2 ELSE c1 END;
END $$;


--
-- Name: to_num(text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.to_num(p text) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE v text := regexp_replace(coalesce(p,''), '[\s$,]', '', 'g');
BEGIN
  IF v ~ '^-?\d+(\.\d+)?$' THEN RETURN v::numeric; END IF;
  RETURN NULL;
EXCEPTION WHEN others THEN RETURN NULL;
END $_$;


--
-- Name: actualizar(integer, jsonb, text); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.actualizar(p_id integer, p jsonb, p_usuario text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE antes jsonb; despues jsonb; k text;
BEGIN
  FOR k IN SELECT jsonb_object_keys(p) LOOP
    IF k NOT IN ('modalidad','cobra_almacenaje','nave','orden_servicio','bultos','unidad_bulto','peso_kg','m2','ubicacion',
                 'fecha_ingreso','horas_montacarga','horas_cuadrilla','observacion') THEN
      RAISE EXCEPTION 'No se puede cambiar el campo %', k;
    END IF;
  END LOOP;
  SELECT to_jsonb(c) INTO antes FROM cs.carga c WHERE id = p_id;
  IF antes IS NULL THEN RAISE EXCEPTION 'No existe la carga %', p_id; END IF;
  UPDATE cs.carga c SET
    modalidad        = CASE WHEN p ? 'modalidad' THEN p->>'modalidad' ELSE c.modalidad END,
    cobra_almacenaje = CASE WHEN p ? 'cobra_almacenaje' THEN (p->>'cobra_almacenaje')::boolean ELSE c.cobra_almacenaje END,
    nave             = CASE WHEN p ? 'nave' THEN nullif(upper(trim(p->>'nave')),'') ELSE c.nave END,
    orden_servicio   = CASE WHEN p ? 'orden_servicio' THEN nullif(trim(p->>'orden_servicio'),'') ELSE c.orden_servicio END,
    bultos           = CASE WHEN p ? 'bultos' THEN nullif(p->>'bultos','')::numeric ELSE c.bultos END,
    unidad_bulto     = CASE WHEN p ? 'unidad_bulto' THEN nullif(upper(trim(p->>'unidad_bulto')),'') ELSE c.unidad_bulto END,
    peso_kg          = CASE WHEN p ? 'peso_kg' THEN nullif(p->>'peso_kg','')::numeric ELSE c.peso_kg END,
    m2               = CASE WHEN p ? 'm2' THEN nullif(p->>'m2','')::numeric ELSE c.m2 END,
    ubicacion        = CASE WHEN p ? 'ubicacion' THEN nullif(upper(trim(p->>'ubicacion')),'') ELSE c.ubicacion END,
    fecha_ingreso    = CASE WHEN p ? 'fecha_ingreso' THEN nullif(p->>'fecha_ingreso','')::date ELSE c.fecha_ingreso END,
    horas_montacarga = CASE WHEN p ? 'horas_montacarga' THEN coalesce(nullif(p->>'horas_montacarga','')::numeric,0) ELSE c.horas_montacarga END,
    horas_cuadrilla  = CASE WHEN p ? 'horas_cuadrilla' THEN coalesce(nullif(p->>'horas_cuadrilla','')::numeric,0) ELSE c.horas_cuadrilla END,
    observacion      = CASE WHEN p ? 'observacion' THEN nullif(trim(p->>'observacion'),'') ELSE c.observacion END
  WHERE id = p_id;
  SELECT to_jsonb(c) INTO despues FROM cs.carga c WHERE id = p_id;
  INSERT INTO cs.evento (carga_id, tipo, detalle, usuario) VALUES (p_id, 'CAMBIO',
    (SELECT jsonb_object_agg(key, jsonb_build_object('antes', antes->key, 'despues', despues->key))
     FROM jsonb_each(despues) WHERE despues->key IS DISTINCT FROM antes->key), p_usuario);
END $$;


--
-- Name: calcular_mes(bigint, date); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.calcular_mes(p_ruc bigint, p_mes date) RETURNS TABLE(carga_id integer, bl text, nave text, orden_servicio text, bultos numeric, unidad_bulto text, peso_kg numeric, ubicacion text, fecha_ingreso date, fecha_salida date, motivo_salida text, dias integer, sobre_umbral boolean, periodos jsonb, importe numeric)
    LANGUAGE plpgsql STABLE
    AS $$
#variable_conflict use_column
DECLARE
  v_cli core.cliente := cs.cliente_por_ruc(p_ruc);
  v_fin date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_tar tarifas.tarifario := cs.tarifario(v_cli.id, v_fin);
BEGIN
  RETURN QUERY
  WITH c AS (
    SELECT c.*, cs.dias_mes(c.fecha_ingreso, c.fecha_salida, p_mes) AS d,
           coalesce(c.peso_kg, 0) >= coalesce(v_tar.umbral_kg, 1000) AS mayor
    FROM cs.carga c
    WHERE c.cliente_id = v_cli.id AND c.cobra_almacenaje
  ), p AS (
    SELECT c.id, per.periodo, per.codigo_rubro,
           greatest(0, least(c.d, coalesce(per.dia_hasta, 100000)) - (per.dia_desde - 1)) AS dp,
           CASE WHEN c.mayor THEN per.tarifa_mayor ELSE per.tarifa_menor END AS tarifa,
           CASE WHEN c.mayor THEN c.peso_kg / 1000.0 ELSE 1 END AS factor
    FROM c JOIN tarifas.cs_periodo per ON per.tarifario_id = v_tar.id
    WHERE c.d > 0
  ), pa AS (
    SELECT p.id, jsonb_agg(jsonb_build_object('periodo', p.periodo, 'dias', p.dp, 'tarifa', p.tarifa,
                 'factor_tn', round(p.factor, 3), 'importe', round(p.dp * p.tarifa * p.factor, 4)) ORDER BY p.periodo) AS periodos,
           round(sum(p.dp * p.tarifa * p.factor), 2) AS importe
    FROM p WHERE p.dp > 0 GROUP BY p.id
  )
  SELECT c.id, c.bl, c.nave, c.orden_servicio, c.bultos, c.unidad_bulto, c.peso_kg, c.ubicacion, c.fecha_ingreso,
         CASE WHEN c.fecha_salida <= v_fin THEN c.fecha_salida END,
         CASE WHEN c.fecha_salida <= v_fin THEN c.motivo_salida END,
         c.d, c.mayor, pa.periodos, pa.importe
  FROM c JOIN pa ON pa.id = c.id
  ORDER BY c.bl;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: carga; Type: TABLE; Schema: cs; Owner: -
--

CREATE TABLE cs.carga (
    id integer NOT NULL,
    cliente_id integer NOT NULL,
    bl text NOT NULL,
    modalidad text NOT NULL,
    cobra_almacenaje boolean NOT NULL,
    nave text,
    orden_servicio text,
    bultos numeric(12,2),
    unidad_bulto text,
    peso_kg numeric(12,2),
    m2 numeric(12,2),
    ubicacion text,
    fecha_ingreso date,
    horas_montacarga numeric(6,2) DEFAULT 0 NOT NULL,
    horas_cuadrilla numeric(6,2) DEFAULT 0 NOT NULL,
    observacion text,
    fecha_salida date,
    motivo_salida text,
    detalle_salida text,
    creado_por text,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT carga_check CHECK (((fecha_salida IS NULL) = (motivo_salida IS NULL))),
    CONSTRAINT carga_check1 CHECK (((fecha_salida IS NULL) OR (fecha_ingreso IS NULL) OR (fecha_salida >= fecha_ingreso))),
    CONSTRAINT carga_modalidad_check CHECK ((modalidad = ANY (ARRAY['ALMACEN'::text, 'DEPOSITO_SIMPLE'::text]))),
    CONSTRAINT carga_motivo_salida_check CHECK ((motivo_salida = ANY (ARRAY['RETIRO'::text, 'DESTRUCCION_SUNAT'::text, 'ADJUDICACION_SUNAT'::text, 'OTRO'::text]))),
    CONSTRAINT carga_peso_kg_check CHECK ((peso_kg >= (0)::numeric))
);


--
-- Name: carga_por_bl(text, bigint); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.carga_por_bl(p_bl text, p_ruc bigint DEFAULT NULL::bigint) RETURNS cs.carga
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE c cs.carga;
BEGIN
  SELECT k.* INTO c FROM cs.carga k JOIN core.cliente cl ON cl.id = k.cliente_id
  WHERE k.bl = upper(trim(p_bl)) AND (p_ruc IS NULL OR cl.ruc = p_ruc)
  ORDER BY (k.fecha_salida IS NULL) DESC, k.fecha_ingreso DESC NULLS LAST, k.id DESC LIMIT 1;
  IF c.id IS NULL THEN RAISE EXCEPTION 'No hay información del BL % en el registro de carga suelta', upper(trim(p_bl)); END IF;
  RETURN c;
END $$;


--
-- Name: cliente; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.cliente (
    id integer NOT NULL,
    ruc bigint,
    razon_social text NOT NULL,
    nombre_corto text NOT NULL,
    alias text[] DEFAULT '{}'::text[] NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    tipo text DEFAULT 'CLIENTE'::text NOT NULL,
    CONSTRAINT cliente_tipo_check CHECK ((tipo = ANY (ARRAY['CLIENTE'::text, 'AGENCIA'::text])))
);


--
-- Name: cliente_por_ruc(bigint); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.cliente_por_ruc(p_ruc bigint) RETURNS core.cliente
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE c core.cliente;
BEGIN
  SELECT * INTO c FROM core.cliente WHERE ruc = coalesce(p_ruc, 20100000017);
  IF c.id IS NULL THEN RAISE EXCEPTION 'No existe el cliente con RUC %', p_ruc; END IF;
  RETURN c;
END $$;


--
-- Name: deposito_json(text, date, jsonb); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.deposito_json(p_bl text, p_fecha_salida date DEFAULT NULL::date, p_ajustes jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  c        cs.carga := cs.carga_por_bl(p_bl);
  v_cli    core.cliente;
  v_sal    date := coalesce(p_fecha_salida, c.fecha_salida, current_date);
  v_tar    tarifas.tarifario := cs.tarifario(c.cliente_id, v_sal);
  v_igv    numeric := (SELECT valor FROM core.parametro WHERE clave = 'IGV');
  v_lineas jsonb;
  v_alert  jsonb := '[]'::jsonb;
  v_dias   int;
BEGIN
  SELECT * INTO v_cli FROM core.cliente WHERE id = c.cliente_id;
  IF c.fecha_ingreso IS NOT NULL AND v_sal < c.fecha_ingreso THEN
    RAISE EXCEPTION 'La fecha de salida (%) es anterior al ingreso (%)', to_char(v_sal,'DD/MM/YYYY'), to_char(c.fecha_ingreso,'DD/MM/YYYY');
  END IF;
  v_dias := v_sal - c.fecha_ingreso;
  v_lineas := liq.aplicar_ajustes(cs.deposito_lineas(p_bl, v_sal), p_ajustes, v_igv);

  IF c.modalidad <> 'DEPOSITO_SIMPLE' THEN
    v_alert := v_alert || jsonb_build_object('nivel','medio','mensaje',
      'Este BL está registrado como carga en almacén: su almacenaje se cobra en la liquidación mensual');
  END IF;
  IF c.fecha_ingreso IS NULL THEN
    v_alert := v_alert || jsonb_build_object('nivel','medio','mensaje','El BL no tiene fecha de ingreso registrada');
  ELSIF v_dias > v_tar.dias_libres THEN
    v_alert := v_alert || jsonb_build_object('nivel','alto','mensaje', format(
      '%s días en depósito: supera los %s días libres. La tarifa de almacenaje para carga terrestre no está definida en el tarifario: confirmar con comercial',
      v_dias, v_tar.dias_libres));
  END IF;
  IF c.horas_montacarga = 0 AND c.horas_cuadrilla = 0 THEN
    v_alert := v_alert || jsonb_build_object('nivel','medio','mensaje','No hay horas de montacarga ni cuadrilla registradas al ingreso');
  END IF;
  IF c.fecha_salida IS NULL THEN
    v_alert := v_alert || jsonb_build_object('nivel','info','mensaje','La carga sigue en stock: al emitir puedes registrar su salida');
  END IF;

  RETURN jsonb_build_object(
    'version_formato', 1,
    'tipo', 'CS_DEPOSITO',
    'emisor', jsonb_build_object('empresa', 'DEPOSITO TEMPORAL DEMO S.A.C.', 'sede', 'CALLAO'),
    'cliente', jsonb_build_object('ruc', v_cli.ruc, 'razon_social', v_cli.razon_social),
    'tarifario', jsonb_build_object('codigo', v_tar.codigo, 'vigente_desde', v_tar.vigente_desde),
    'servicio', jsonb_build_object(
        'bl', c.bl, 'contenedor', 'CARGA SUELTA', 'descripcion', 'Carga suelta en depósito simple',
        'carga_id', c.id, 'nave', c.nave, 'orden_servicio', c.orden_servicio, 'bultos', c.bultos,
        'unidad_bulto', c.unidad_bulto, 'peso_kg', c.peso_kg, 'm2', c.m2, 'ubicacion', c.ubicacion,
        'horas_montacarga_ingreso', c.horas_montacarga, 'horas_cuadrilla_ingreso', c.horas_cuadrilla,
        'fecha_ingreso', c.fecha_ingreso, 'fecha_retiro', v_sal, 'dias_en_deposito', v_dias, 'dias_libres', v_tar.dias_libres),
    'moneda', 'USD',
    'igv_tasa', v_igv,
    'lineas', v_lineas,
    'totales', liq.totales(v_lineas),
    'totales_por_unidad', liq.totales_por_unidad(v_lineas),
    'alertas', v_alert);
END $$;


--
-- Name: deposito_lineas(text, date); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.deposito_lineas(p_bl text, p_fecha_salida date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  c      cs.carga := cs.carga_por_bl(p_bl);
  v_sal  date := coalesce(p_fecha_salida, c.fecha_salida, current_date);
  v_tar  tarifas.tarifario := cs.tarifario(c.cliente_id, v_sal);
BEGIN
  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'item', r.n, 'regla_id', r.id, 'codigo_rubro', r.codigo_rubro,
      'concepto', r.concepto, 'unidad_negocio', r.unidad_negocio,
      'origen', CASE WHEN r.disparador = 'MANUAL' THEN 'MANUAL' ELSE 'TARIFARIO' END,
      'tarifa', r.monto,
      'cantidad', CASE r.disparador
                    WHEN 'CS_INGRESO'    THEN 1
                    WHEN 'CS_TRANSPORTE' THEN 2
                    WHEN 'CS_MONTACARGA' THEN c.horas_montacarga * 2   -- horas de recepción + las mismas para despacho
                    WHEN 'CS_CUADRILLA'  THEN c.horas_cuadrilla * 2
                    ELSE 1 END,
      'unidad', r.unidad,
      'opcional', r.disparador = 'MANUAL' OR r.removible,
      'incluido', r.disparador <> 'MANUAL',
      'editable', r.disparador <> 'CS_INGRESO',
      'nota', CASE r.disparador
                WHEN 'CS_MONTACARGA' THEN format('%s h al recibir + %s h al despachar', c.horas_montacarga, c.horas_montacarga)
                WHEN 'CS_CUADRILLA'  THEN format('%s h al recibir + %s h al despachar', c.horas_cuadrilla, c.horas_cuadrilla)
                WHEN 'CS_TRANSPORTE' THEN 'Vueltas de transporte'
                ELSE r.pendiente END)
      ORDER BY r.orden, r.id), '[]'::jsonb)
    FROM (SELECT g.*, row_number() OVER (ORDER BY g.orden, g.id) AS n
          FROM tarifas.regla g WHERE g.tarifario_id = v_tar.id AND g.activo) r);
END $$;


--
-- Name: dias_mes(date, date, date); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.dias_mes(p_ingreso date, p_salida date, p_mes date) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT greatest(0,
    least(coalesce(p_salida, fin), fin) - greatest(coalesce(p_ingreso, ini - 1), ini - 1))
  FROM (SELECT date_trunc('month', p_mes)::date AS ini,
               (date_trunc('month', p_mes) + interval '1 month - 1 day')::date AS fin) m
$$;


--
-- Name: emitir_deposito(text, date, jsonb, text, text, boolean); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.emitir_deposito(p_bl text, p_fecha_salida date, p_ajustes jsonb DEFAULT '{}'::jsonb, p_usuario text DEFAULT NULL::text, p_origen text DEFAULT 'REAL'::text, p_registrar_salida boolean DEFAULT true) RETURNS TABLE(liquidacion_id bigint, version integer, reemplazo_id bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
  c cs.carga := cs.carga_por_bl(p_bl);
  v_sal date := coalesce(p_fecha_salida, c.fecha_salida, current_date);
BEGIN
  IF p_registrar_salida AND c.fecha_salida IS NULL AND p_origen = 'REAL' THEN
    PERFORM cs.registrar_salida(c.id, v_sal, 'RETIRO', 'Registrada al emitir la liquidación', p_usuario);
  END IF;
  RETURN QUERY SELECT * FROM liq.guardar(cs.deposito_json(p_bl, v_sal, p_ajustes), v_sal, 'CS_DEPOSITO', p_usuario, p_origen);
END $$;


--
-- Name: emitir_mensual(bigint, date, jsonb, text, text); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.emitir_mensual(p_ruc bigint, p_mes date, p_ajustes jsonb DEFAULT '{}'::jsonb, p_usuario text DEFAULT NULL::text, p_origen text DEFAULT 'REAL'::text) RETURNS TABLE(liquidacion_id bigint, version integer, reemplazo_id bigint)
    LANGUAGE sql
    AS $$
  SELECT * FROM liq.guardar(cs.mensual_json(p_ruc, p_mes, p_ajustes),
                            (date_trunc('month', p_mes) + interval '1 month - 1 day')::date, 'CS_MENSUAL', p_usuario, p_origen)
$$;


--
-- Name: mensual_json(bigint, date, jsonb); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.mensual_json(p_ruc bigint, p_mes date, p_ajustes jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_cli    core.cliente := cs.cliente_por_ruc(p_ruc);
  v_ini    date := date_trunc('month', p_mes)::date;
  v_fin    date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_tar    tarifas.tarifario := cs.tarifario(v_cli.id, v_fin);
  v_igv    numeric := (SELECT valor FROM core.parametro WHERE clave = 'IGV');
  v_all    jsonb := cs.mensual_lineas(v_cli.ruc, p_mes);
  v_lineas jsonb;
  v_det    jsonb;
  v_alert  jsonb := '[]'::jsonb;
  v_excl   jsonb := coalesce(p_ajustes->'excluir', '[]');
BEGIN
  v_lineas := liq.aplicar_ajustes(v_all, p_ajustes, v_igv);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'bl', m.bl, 'nave', m.nave, 'orden_servicio', m.orden_servicio, 'bultos', m.bultos, 'unidad_bulto', m.unidad_bulto,
           'peso_kg', m.peso_kg, 'ubicacion', m.ubicacion, 'fecha_ingreso', m.fecha_ingreso, 'fecha_salida', m.fecha_salida,
           'motivo_salida', m.motivo_salida, 'dias', m.dias, 'tarifa_por_tonelada', m.sobre_umbral,
           'periodos', m.periodos, 'importe', m.importe) ORDER BY m.bl), '[]'::jsonb)
  INTO v_det
  FROM cs.calcular_mes(v_cli.ruc, p_mes) m
  WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_all) x
                    WHERE x->>'bl' = m.bl AND v_excl @> to_jsonb((x->>'item')::int));

  IF jsonb_array_length(v_det) = 0 THEN
    v_alert := v_alert || jsonb_build_object('nivel','alto','mensaje','No hay carga en stock con almacenaje en este mes');
  END IF;
  IF v_fin >= current_date THEN
    v_alert := v_alert || jsonb_build_object('nivel','medio','mensaje',
      'El mes aún no termina: se calcula hasta el ' || to_char(v_fin, 'DD/MM/YYYY') || ' asumiendo que la carga sigue en stock');
  END IF;
  IF jsonb_array_length(v_excl) > 0 AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_all) x
       WHERE x->>'origen' = 'ALMACENAJE_CS' AND v_excl @> to_jsonb((x->>'item')::int)) THEN
    v_alert := v_alert || jsonb_build_object('nivel','medio','mensaje','Se quitaron BLs de esta liquidación');
  END IF;
  IF EXISTS (SELECT 1 FROM cs.calcular_mes(v_cli.ruc, p_mes) m WHERE m.fecha_salida IS NOT NULL) THEN
    v_alert := v_alert || jsonb_build_object('nivel','info','mensaje',
      (SELECT string_agg(format('%s salió el %s (%s): se cobran %s días', m.bl, to_char(m.fecha_salida,'DD/MM'),
               replace(lower(m.motivo_salida),'_',' '), m.dias), '; ' ORDER BY m.fecha_salida)
       FROM cs.calcular_mes(v_cli.ruc, p_mes) m WHERE m.fecha_salida IS NOT NULL));
  END IF;
  IF EXISTS (SELECT 1 FROM cs.calcular_mes(v_cli.ruc, p_mes) m WHERE m.fecha_ingreso >= v_ini) THEN
    v_alert := v_alert || jsonb_build_object('nivel','info','mensaje',
      (SELECT string_agg(format('%s ingresó el %s: se cobran %s días', m.bl, to_char(m.fecha_ingreso,'DD/MM'), m.dias), '; ' ORDER BY m.fecha_ingreso)
       FROM cs.calcular_mes(v_cli.ruc, p_mes) m WHERE m.fecha_ingreso >= v_ini));
  END IF;

  RETURN jsonb_build_object(
    'version_formato', 1,
    'tipo', 'CS_MENSUAL',
    'emisor', jsonb_build_object('empresa', 'DEPOSITO TEMPORAL DEMO S.A.C.', 'sede', 'CALLAO'),
    'cliente', jsonb_build_object('ruc', v_cli.ruc, 'razon_social', v_cli.razon_social),
    'tarifario', jsonb_build_object('codigo', v_tar.codigo, 'vigente_desde', v_tar.vigente_desde),
    'servicio', jsonb_build_object(
        'bl', 'ALMACEN CS ' || to_char(v_ini, 'YYYY-MM'), 'contenedor', 'CARGA SUELTA',
        'descripcion', 'Almacenaje de carga suelta en stock',
        'periodo', to_char(v_ini, 'YYYY-MM'), 'desde', v_ini, 'hasta', v_fin, 'fecha_retiro', v_fin,
        'bls', jsonb_array_length(v_det)),
    'detalle', v_det,
    'moneda', 'USD',
    'igv_tasa', v_igv,
    'lineas', v_lineas,
    'totales', liq.totales(v_lineas),
    'totales_por_unidad', liq.totales_por_unidad(v_lineas),
    'alertas', v_alert);
END $$;


--
-- Name: mensual_lineas(bigint, date); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.mensual_lineas(p_ruc bigint, p_mes date) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_cli core.cliente := cs.cliente_por_ruc(p_ruc);
  v_fin date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
  v_tar tarifas.tarifario := cs.tarifario(v_cli.id, v_fin);
  v_bls jsonb; v_extra jsonb; v_n int;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'item', m.n, 'regla_id', NULL, 'codigo_rubro', 801,
           'concepto', format('ALMACENAJE CS - BL %s (%s días%s)', m.bl, m.dias,
                              CASE WHEN m.sobre_umbral THEN ', ' || round(m.peso_kg / 1000.0, 3) || ' TN' ELSE '' END),
           'unidad_negocio', 'DT', 'origen', 'ALMACENAJE_CS', 'tarifa', m.importe, 'cantidad', 1, 'unidad', 'BL',
           'opcional', true, 'incluido', true, 'editable', false, 'nota', NULL, 'bl', m.bl) ORDER BY m.bl), '[]'::jsonb),
         count(*)
  INTO v_bls, v_n
  FROM (SELECT k.*, row_number() OVER (ORDER BY k.bl) AS n FROM cs.calcular_mes(v_cli.ruc, p_mes) k) m;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'item', 1000 + r.n, 'regla_id', r.id,
           'codigo_rubro', r.codigo_rubro, 'concepto', r.concepto, 'unidad_negocio', r.unidad_negocio,
           'origen', 'MANUAL', 'tarifa', r.monto, 'cantidad', CASE WHEN r.unidad = 'BL' THEN greatest(v_n, 1) ELSE 1 END,
           'unidad', r.unidad, 'opcional', true, 'incluido', false, 'editable', true, 'nota', r.pendiente)
           ORDER BY r.orden, r.id), '[]'::jsonb)
  INTO v_extra
  FROM (SELECT g.*, row_number() OVER (ORDER BY g.orden, g.id) AS n
        FROM tarifas.regla g WHERE g.tarifario_id = v_tar.id AND g.activo) r;

  RETURN v_bls || v_extra;
END $$;


--
-- Name: registrar_ingreso(jsonb, text); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.registrar_ingreso(p jsonb, p_usuario text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_cli  core.cliente := cs.cliente_por_ruc(nullif(p->>'ruc','')::bigint);
  v_mod  text := coalesce(nullif(p->>'modalidad',''), 'ALMACEN');
  v_bl   text := upper(trim(p->>'bl'));
  v_id   int;
BEGIN
  IF coalesce(v_bl, '') = '' THEN RAISE EXCEPTION 'Indique el BL'; END IF;
  IF v_mod = 'ALMACEN' AND nullif(p->>'peso_kg','') IS NULL THEN
    RAISE EXCEPTION 'Indique el peso (kg): define la tarifa de almacenaje';
  END IF;
  IF EXISTS (SELECT 1 FROM cs.carga WHERE cliente_id = v_cli.id AND bl = v_bl AND fecha_salida IS NULL) THEN
    RAISE EXCEPTION 'El BL % ya está en stock', v_bl;
  END IF;
  INSERT INTO cs.carga (cliente_id, bl, modalidad, cobra_almacenaje, nave, orden_servicio, bultos, unidad_bulto,
                        peso_kg, m2, ubicacion, fecha_ingreso, horas_montacarga, horas_cuadrilla, observacion, creado_por)
  VALUES (v_cli.id, v_bl, v_mod,
          coalesce((p->>'cobra_almacenaje')::boolean, v_mod = 'ALMACEN'),
          nullif(upper(trim(p->>'nave')),''), nullif(trim(p->>'orden_servicio'),''),
          nullif(p->>'bultos','')::numeric, nullif(upper(trim(p->>'unidad_bulto')),''),
          nullif(p->>'peso_kg','')::numeric, nullif(p->>'m2','')::numeric, nullif(upper(trim(p->>'ubicacion')),''),
          nullif(p->>'fecha_ingreso','')::date,
          coalesce(nullif(p->>'horas_montacarga','')::numeric, 0), coalesce(nullif(p->>'horas_cuadrilla','')::numeric, 0),
          nullif(trim(p->>'observacion'),''), p_usuario)
  RETURNING id INTO v_id;
  INSERT INTO cs.evento (carga_id, tipo, detalle, usuario) VALUES (v_id, 'INGRESO', p, p_usuario);
  RETURN v_id;
END $$;


--
-- Name: registrar_salida(integer, date, text, text, text); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.registrar_salida(p_id integer, p_fecha date, p_motivo text, p_detalle text DEFAULT NULL::text, p_usuario text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE c cs.carga;
BEGIN
  SELECT * INTO c FROM cs.carga WHERE id = p_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'No existe la carga %', p_id; END IF;
  IF c.fecha_salida IS NOT NULL THEN RAISE EXCEPTION 'El BL % ya salió el %', c.bl, to_char(c.fecha_salida, 'DD/MM/YYYY'); END IF;
  IF p_fecha IS NULL THEN RAISE EXCEPTION 'Indique la fecha de salida'; END IF;
  IF c.fecha_ingreso IS NOT NULL AND p_fecha < c.fecha_ingreso THEN
    RAISE EXCEPTION 'La fecha de salida es anterior al ingreso (%)', to_char(c.fecha_ingreso, 'DD/MM/YYYY');
  END IF;
  IF p_motivo = 'OTRO' AND coalesce(trim(p_detalle), '') = '' THEN RAISE EXCEPTION 'Explique el motivo de la salida'; END IF;
  UPDATE cs.carga SET fecha_salida = p_fecha, motivo_salida = p_motivo, detalle_salida = nullif(trim(p_detalle), '')
  WHERE id = p_id;
  INSERT INTO cs.evento (carga_id, tipo, detalle, usuario)
  VALUES (p_id, 'SALIDA', jsonb_build_object('fecha', p_fecha, 'motivo', p_motivo, 'detalle', p_detalle), p_usuario);
END $$;


--
-- Name: revertir_salida(integer, text, text); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.revertir_salida(p_id integer, p_motivo text, p_usuario text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE c cs.carga;
BEGIN
  SELECT * INTO c FROM cs.carga WHERE id = p_id FOR UPDATE;
  IF c.fecha_salida IS NULL THEN RAISE EXCEPTION 'El BL no tiene salida registrada'; END IF;
  IF coalesce(trim(p_motivo), '') = '' THEN RAISE EXCEPTION 'Indique por qué se revierte la salida'; END IF;
  IF EXISTS (SELECT 1 FROM cs.carga WHERE cliente_id = c.cliente_id AND bl = c.bl AND fecha_salida IS NULL) THEN
    RAISE EXCEPTION 'El BL % ya tiene otro ingreso en stock', c.bl;
  END IF;
  INSERT INTO cs.evento (carga_id, tipo, detalle, usuario) VALUES (p_id, 'SALIDA_REVERTIDA',
    jsonb_build_object('fecha', c.fecha_salida, 'motivo', c.motivo_salida, 'detalle', c.detalle_salida, 'razon', p_motivo), p_usuario);
  UPDATE cs.carga SET fecha_salida = NULL, motivo_salida = NULL, detalle_salida = NULL WHERE id = p_id;
END $$;


--
-- Name: tarifario; Type: TABLE; Schema: tarifas; Owner: -
--

CREATE TABLE tarifas.tarifario (
    id integer NOT NULL,
    cliente_id integer NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    operacion text DEFAULT 'IMPO_FCL'::text NOT NULL,
    vigente_desde date NOT NULL,
    vigente_hasta date,
    dias_libres integer DEFAULT 30 NOT NULL,
    documento text,
    notas text,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    umbral_kg numeric(12,2),
    CONSTRAINT tarifario_check CHECK (((vigente_hasta IS NULL) OR (vigente_hasta >= vigente_desde))),
    CONSTRAINT tarifario_operacion_check CHECK ((operacion = ANY (ARRAY['IMPO_FCL'::text, 'EXPO_FCL'::text, 'CARGA_SUELTA'::text])))
);


--
-- Name: tarifario(integer, date); Type: FUNCTION; Schema: cs; Owner: -
--

CREATE FUNCTION cs.tarifario(p_cliente integer, p_fecha date) RETURNS tarifas.tarifario
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE t tarifas.tarifario;
BEGIN
  SELECT * INTO t FROM tarifas.tarifario
  WHERE cliente_id = p_cliente AND operacion = 'CARGA_SUELTA' AND vigente_desde <= p_fecha
    AND (vigente_hasta IS NULL OR vigente_hasta >= p_fecha)
  ORDER BY vigente_desde DESC LIMIT 1;
  IF t.id IS NULL THEN RAISE EXCEPTION 'No hay tarifario de carga suelta vigente al %', to_char(p_fecha, 'DD/MM/YYYY'); END IF;
  RETURN t;
END $$;


--
-- Name: campos_faltantes(jsonb); Type: FUNCTION; Schema: dt; Owner: -
--

CREATE FUNCTION dt.campos_faltantes(d jsonb) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT coalesce((SELECT array_agg(etiqueta ORDER BY orden) FROM (VALUES
      (1, 'clase_cnt',             'clase (ST/HC/RH)'),
      (2, 'tamano_cnt',            'tamaño'),
      (3, 'tipo_carga',            'tipo de carga'),
      (4, 'fecha_ingreso_balanza', 'fecha de ingreso'),
      (5, 'operador_portuario',    'puerto (APM/DPW)'),
      (6, 'conexion',              'conexión'),
      (7, 'cliente',               'cliente')
    ) c(orden, campo, etiqueta)
    WHERE nullif(trim(d->>campo), '') IS NULL
       OR (campo = 'fecha_ingreso_balanza' AND core.to_fecha(d->>campo) IS NULL)), '{}'::text[])
  || CASE WHEN upper(d->>'tipo_carga') = 'IMO' AND nullif(trim(d->>'clase_imo'), '') IS NULL
          THEN ARRAY['clase IMO'] ELSE '{}'::text[] END
$$;


--
-- Name: contenedor; Type: TABLE; Schema: dt; Owner: -
--

CREATE TABLE dt.contenedor (
    tipo_servicio character varying NOT NULL,
    bk character varying NOT NULL,
    orden_servicio integer,
    cod_linea integer,
    linea_maritima character varying,
    codigo_nave character varying,
    nave character varying,
    numero_viaje integer,
    cod_agen_maritimo integer,
    agente_maritimo character varying,
    cod_agencia integer,
    agencia_aduana character varying,
    ruc_agencia_aduana bigint,
    codigo_puerto_destino character varying,
    puerto_destino character varying,
    codigo_puerto_origen character varying,
    puerto_origen character varying,
    sede character varying,
    lugar_llenado character varying,
    contenedor character varying NOT NULL,
    clase_cnt character varying NOT NULL,
    tamano_cnt smallint NOT NULL,
    isotype character varying,
    condicion_cnt character varying NOT NULL,
    tipo_carga character varying NOT NULL,
    clase_imo character varying,
    fecha_ingreso_balanza date NOT NULL,
    hora_ingreso_balanza time without time zone NOT NULL,
    cliente character varying NOT NULL,
    ruc_cliente bigint,
    mercaderia character varying,
    operador_portuario character varying,
    conexion boolean NOT NULL,
    temperatura numeric,
    tipo_inspeccion character varying,
    zona character varying,
    balancero character varying,
    guia_ingreso bigint,
    nro_mercaderia smallint,
    CONSTRAINT contenedor_operador_portuario_check CHECK (((operador_portuario)::text = ANY ((ARRAY['APM'::character varying, 'DPW'::character varying])::text[]))),
    CONSTRAINT contenedor_tipo_servicio_check CHECK (((tipo_servicio)::text = ANY ((ARRAY['IMPO'::character varying, 'EXPO'::character varying])::text[])))
);


--
-- Name: acuerdo(dt.contenedor, date); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.acuerdo(c dt.contenedor, p_fecha date) RETURNS TABLE(parte_id integer, tipo text, tarifario_id integer)
    LANGUAGE sql STABLE
    AS $$
  WITH partes AS (
    SELECT cl.id, cl.tipo, 1 AS prioridad FROM core.cliente cl
    WHERE cl.tipo = 'AGENCIA' AND cl.activo
      AND (cl.ruc = c.ruc_agencia_aduana
           OR EXISTS (SELECT 1 FROM unnest(cl.alias) a WHERE core.norm(c.agencia_aduana) LIKE '%' || core.norm(a) || '%'))
    UNION ALL
    SELECT cl.id, cl.tipo, 2 FROM core.cliente cl
    WHERE cl.tipo = 'CLIENTE' AND cl.activo
      AND (cl.ruc = c.ruc_cliente OR core.norm(c.cliente) = ANY (SELECT core.norm(a) FROM unnest(cl.alias) a))
  )
  SELECT p.id, p.tipo, t.id
  FROM partes p
  JOIN LATERAL (SELECT t.id FROM tarifas.tarifario t
                WHERE t.cliente_id = p.id AND t.operacion = 'IMPO_FCL' AND t.vigente_desde <= p_fecha
                  AND (t.vigente_hasta IS NULL OR t.vigente_hasta >= p_fecha)
                ORDER BY t.vigente_desde DESC LIMIT 1) t ON true
  ORDER BY p.prioridad
  LIMIT 1
$$;


--
-- Name: anular(bigint, text, text); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.anular(p_id bigint, p_motivo text, p_usuario text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF coalesce(trim(p_motivo), '') = '' THEN RAISE EXCEPTION 'Indique el motivo de la anulación'; END IF;
  UPDATE liq.liquidacion SET estado = 'ANULADA',
         anulado_motivo = trim(p_motivo) || coalesce(' (' || p_usuario || ')', ''), anulado_en = now()
  WHERE id = p_id AND estado IN ('EMITIDA','FACTURADA');
  IF NOT FOUND THEN RAISE EXCEPTION 'La liquidación % no está activa', p_id; END IF;
END $$;


--
-- Name: aplicar_ajustes(jsonb, jsonb, numeric); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.aplicar_ajustes(p_all jsonb, p_ajustes jsonb, p_igv numeric) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
  WITH l AS (
    SELECT * FROM jsonb_to_recordset(p_all) AS x(item int, codigo_rubro int, concepto text, unidad_negocio text,
           origen text, tarifa numeric, cantidad numeric, unidad text, opcional boolean, incluido boolean, editable boolean)
  ), aj AS (
    SELECT l.*,
      CASE WHEN l.opcional AND coalesce(p_ajustes->'excluir', '[]') @> to_jsonb(l.item) THEN false
           WHEN l.opcional AND coalesce(p_ajustes->'incluir', '[]') @> to_jsonb(l.item) THEN true
           ELSE l.incluido END AS va,
      CASE WHEN l.editable AND p_ajustes->'cantidades' ? l.item::text
           THEN greatest((p_ajustes->'cantidades'->>l.item::text)::numeric, 0) ELSE l.cantidad END AS cant,
      CASE WHEN l.origen = 'MANUAL' AND p_ajustes->'tarifas' ? l.item::text
           THEN greatest((p_ajustes->'tarifas'->>l.item::text)::numeric, 0) ELSE l.tarifa END AS tar
    FROM l
  ), fin AS (
    SELECT aj.*, round(aj.tar * aj.cant, 2) AS neto, row_number() OVER (ORDER BY aj.item) AS n
    FROM aj WHERE aj.va AND aj.cant > 0
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'item', n, 'rubro', codigo_rubro, 'concepto', concepto, 'unidad_negocio', unidad_negocio,
           'origen', origen, 'tarifa', tar, 'cantidad', cant, 'unidad', unidad,
           'neto', neto, 'igv', round(neto * p_igv, 2), 'total', neto + round(neto * p_igv, 2)) ORDER BY n), '[]'::jsonb)
  FROM fin
$$;


--
-- Name: contenedor_dt(text, date, text); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.contenedor_dt(p_contenedor text, p_fecha_retiro date, p_bl text DEFAULT NULL::text) RETURNS dt.contenedor
    LANGUAGE sql STABLE
    AS $$
  SELECT c.* FROM dt.contenedor c
  WHERE c.contenedor = upper(trim(p_contenedor))
    AND (p_bl IS NULL OR c.bk = upper(trim(p_bl)))
    AND c.fecha_ingreso_balanza <= p_fecha_retiro
  ORDER BY c.fecha_ingreso_balanza DESC
  LIMIT 1
$$;


--
-- Name: contenedores_de_bl(text); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.contenedores_de_bl(p_bl text) RETURNS TABLE(contenedor text, completo boolean)
    LANGUAGE sql STABLE
    AS $$
  SELECT c.contenedor, true FROM dt.contenedor c WHERE c.bk = upper(trim(p_bl))
  UNION
  SELECT p.contenedor, false FROM dt.contenedor_pendiente p
  WHERE p.bk = upper(trim(p_bl)) AND NOT EXISTS (SELECT 1 FROM dt.contenedor c WHERE c.contenedor = p.contenedor AND c.bk = p.bk)
  ORDER BY 1
$$;


--
-- Name: cotizar(text, date, text); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.cotizar(p_contenedor text, p_fecha_retiro date, p_bl text DEFAULT NULL::text) RETURNS TABLE(item integer, regla_id integer, codigo_rubro integer, concepto text, unidad_negocio text, origen text, tarifa numeric, cantidad numeric, unidad text, opcional boolean, incluido boolean, nota text)
    LANGUAGE plpgsql STABLE
    AS $$
#variable_conflict use_column
DECLARE
  c            dt.contenedor;
  v_tarifario  tarifas.tarifario;
  v_conexion   boolean;
  v_tipo_base  text;
  v_grupo      char(1);
  v_dias_rh    int;
  v_dias_alm   int;
  v_msg        text;
  n_cuad int; n_mont int; n_manip int; n_sini int;
BEGIN
  c := liq.contenedor_dt(p_contenedor, p_fecha_retiro, p_bl);
  IF c.contenedor IS NULL THEN
    SELECT x.* INTO c FROM dt.contenedor x WHERE x.contenedor = upper(trim(p_contenedor))
    ORDER BY x.fecha_ingreso_balanza DESC LIMIT 1;
    IF c.contenedor IS NOT NULL THEN
      RAISE EXCEPTION 'La fecha de retiro (%) es anterior al ingreso del contenedor % al DT (%, BL %)',
        to_char(p_fecha_retiro,'DD/MM/YYYY'), c.contenedor, to_char(c.fecha_ingreso_balanza,'DD/MM/YYYY'), c.bk USING ERRCODE = 'P0002';
    END IF;
    SELECT 'El contenedor ' || p.contenedor || ' (BL ' || p.bk || ') está en la data del DT pero le falta: ' || array_to_string(p.faltan, ', ')
      INTO v_msg FROM dt.contenedor_pendiente p WHERE p.contenedor = upper(trim(p_contenedor)) LIMIT 1;
    IF v_msg IS NOT NULL THEN RAISE EXCEPTION '%', v_msg USING ERRCODE = 'P0002'; END IF;
    RAISE EXCEPTION 'No hay información del contenedor % en la data del DT', upper(p_contenedor) USING ERRCODE = 'P0002';
  END IF;

  SELECT t.* INTO v_tarifario FROM liq.acuerdo(c, p_fecha_retiro) a JOIN tarifas.tarifario t ON t.id = a.tarifario_id;
  IF v_tarifario.id IS NULL THEN
    RAISE EXCEPTION 'No hay acuerdo comercial vigente al % para el cliente % ni para su agencia de aduana %',
      to_char(p_fecha_retiro,'DD/MM/YYYY'), c.cliente, coalesce(c.agencia_aduana, '(sin agencia)') USING ERRCODE = 'P0002';
  END IF;

  v_conexion  := (c.clase_cnt = 'RH' AND c.conexion);
  v_tipo_base := CASE WHEN v_conexion THEN 'RH' ELSE 'DRY' END;
  v_dias_rh   := p_fecha_retiro - c.fecha_ingreso_balanza + 1;
  v_dias_alm  := greatest(0, (p_fecha_retiro - c.fecha_ingreso_balanza) - v_tarifario.dias_libres);  -- días en depósito = retiro - ingreso; se cobra lo que pase de los días libres
  IF c.tipo_carga = 'IMO' THEN
    SELECT i.grupo INTO v_grupo FROM tarifas.imo_clase i WHERE i.clase = c.clase_imo;
    IF v_grupo IS NULL THEN
      RAISE EXCEPTION 'Clase IMO % sin grupo asignado', c.clase_imo;
    END IF;
  END IF;

  -- Eventos de Control Movilizaciones entre el ingreso y el retiro
  SELECT count(*) FILTER (WHERE m.cuadrilla), count(*) FILTER (WHERE m.montacarga OR m.montacarga_5tm),
         count(*) FILTER (WHERE m.manipuleo)
  INTO n_cuad, n_mont, n_manip
  FROM ops.movilizacion m
  WHERE m.contenedor = c.contenedor AND m.fecha BETWEEN c.fecha_ingreso_balanza AND p_fecha_retiro;

  -- Movilizaciones a SINI registradas por el puerto
  SELECT count(*) INTO n_sini FROM ops.servicio_adicional s
  JOIN tarifas.recupero_concepto rc ON rc.concepto = s.concepto AND rc.tratamiento = 'DISPARA_SINI'
  WHERE s.contenedor = c.contenedor
    AND coalesce(s.fecha_desde, s.fecha_recepcion) BETWEEN c.fecha_ingreso_balanza - 30 AND p_fecha_retiro + 60
    AND s.factura_proveedor IS NOT NULL AND s.factura_proveedor NOT LIKE 'ASUME%'
    AND coalesce(s.cliente, '') NOT LIKE 'ASUME%' AND coalesce(s.area, '') NOT LIKE 'ASUME%';

  RETURN QUERY
  WITH sa AS (
    -- Facturación del puerto a trasladar al cliente: con factura, no asumida por el depósito, conceptos a refacturar
    SELECT s.* FROM ops.servicio_adicional s
    JOIN tarifas.recupero_concepto rc ON rc.concepto = s.concepto AND rc.tratamiento = 'REFACTURAR'
    WHERE s.contenedor = c.contenedor
      AND coalesce(s.fecha_desde, s.fecha_recepcion) BETWEEN c.fecha_ingreso_balanza - 30 AND p_fecha_retiro + 60
      AND s.factura_proveedor IS NOT NULL AND s.factura_proveedor NOT LIKE 'ASUME%'
      AND coalesce(s.cliente, '') NOT LIKE 'ASUME%' AND coalesce(s.area, '') NOT LIKE 'ASUME%'
      AND coalesce(s.monto_usd, 0) > 0
  ),
  reglas AS (
    SELECT r.*,
      CASE r.disparador
        WHEN 'SIEMPRE'    THEN CASE WHEN r.tipo_carga IN (v_tipo_base, 'TODOS') THEN 1 ELSE 0 END
        WHEN 'CONEXION'   THEN CASE WHEN v_conexion THEN CASE WHEN r.unidad = 'DIA' THEN v_dias_rh ELSE 1 END ELSE 0 END
        WHEN 'DPW'        THEN CASE WHEN c.operador_portuario = 'DPW' THEN 1 ELSE 0 END
        WHEN 'IMO'        THEN CASE WHEN c.tipo_carga = 'IMO' AND (r.grupo_imo IS NULL OR r.grupo_imo = v_grupo) THEN 1 ELSE 0 END
        WHEN 'CUADRILLA'  THEN n_cuad
        WHEN 'MONTACARGA' THEN n_mont
        WHEN 'MANIPULEO'  THEN n_manip
        WHEN 'SINI'       THEN n_sini
        WHEN 'ALMACENAJE' THEN v_dias_alm
        ELSE 0
      END::numeric AS cant
    FROM tarifas.regla r
    WHERE r.tarifario_id = v_tarifario.id AND r.activo
      AND r.puerto IN (c.operador_portuario, 'TODOS')
      AND r.tamano IN (c.tamano_cnt::text, 'TODOS')
      AND (r.disparador <> 'IMO' OR r.tipo_carga IN ('IMO','TODOS'))
  ),
  lineas AS (
    -- Reglas automáticas
    SELECT r.orden, r.id AS regla_id, r.codigo_rubro, r.concepto, r.unidad_negocio, 'TARIFARIO'::text AS origen,
           r.monto AS tarifa, r.cant AS cantidad, r.unidad, r.removible AS opcional, true AS incluido, r.pendiente AS nota
    FROM reglas r WHERE r.disparador NOT IN ('MANUAL','RECUPERO_ADMIN') AND r.cant > 0
    UNION ALL
    -- Sobrecostos del puerto a refacturar (el ejecutivo decide)
    SELECT 80, NULL, NULL,
           s.concepto || coalesce(' - ' || s.proveedor, ''),
           'DT', 'SERV_ADICIONAL', round(s.monto_usd, 2), 1::numeric, 'EVENTO', true, true,
           nullif(concat_ws(' | ', s.descripcion, 'Fact. puerto ' || s.factura_proveedor), '')
    FROM sa s
    UNION ALL
    -- Gasto administrativo por recupero
    SELECT r.orden, r.id, r.codigo_rubro, r.concepto, r.unidad_negocio, 'TARIFARIO', r.monto, 1::numeric, r.unidad, true,
           true, r.pendiente
    FROM reglas r WHERE r.disparador = 'RECUPERO_ADMIN' AND EXISTS (SELECT 1 FROM sa)
    UNION ALL
    -- Opcionales manuales (pernocte, congestión, memo APM/DPW, stand by)
    SELECT r.orden, r.id, r.codigo_rubro, r.concepto, r.unidad_negocio, 'MANUAL', r.monto, 1::numeric, r.unidad, true, false, r.pendiente
    FROM reglas r WHERE r.disparador = 'MANUAL'
  )
  SELECT (row_number() OVER (ORDER BY l.orden, l.codigo_rubro NULLS LAST, l.concepto))::int,
         l.regla_id, l.codigo_rubro, l.concepto, l.unidad_negocio, l.origen, l.tarifa, l.cantidad, l.unidad,
         l.opcional, l.incluido, l.nota
  FROM lineas l
  ORDER BY 1;
END $$;


--
-- Name: cotizar_json(text, date, text, jsonb); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.cotizar_json(p_contenedor text, p_fecha_retiro date, p_bl text DEFAULT NULL::text, p_ajustes jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  c         dt.contenedor;
  v_cli     core.cliente;
  v_tar     tarifas.tarifario;
  v_ac      record;
  v_fac     jsonb;
  v_igv     numeric;
  v_all     jsonb;
  v_lineas  jsonb;
  v_alertas jsonb := '[]'::jsonb;
  v_mov     jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY l.item), '[]'::jsonb) INTO v_all
  FROM liq.cotizar(p_contenedor, p_fecha_retiro, p_bl) l;   -- valida y lanza error si falta algo
  c := liq.contenedor_dt(p_contenedor, p_fecha_retiro, p_bl);
  SELECT valor INTO v_igv FROM core.parametro WHERE clave = 'IGV';

  SELECT a.* INTO v_ac FROM liq.acuerdo(c, p_fecha_retiro) a;
  SELECT cl.* INTO v_cli FROM core.cliente cl WHERE cl.id = v_ac.parte_id;
  SELECT t.* INTO v_tar FROM tarifas.tarifario t WHERE t.id = v_ac.tarifario_id;
  -- Se factura al cliente (consignatario). En acuerdo con el cliente se usan sus datos registrados.
  IF v_ac.tipo = 'CLIENTE' THEN
    v_fac := jsonb_build_object('ruc', v_cli.ruc, 'razon_social', v_cli.razon_social);
  ELSE
    v_fac := jsonb_build_object('ruc', c.ruc_cliente, 'razon_social', c.cliente);
  END IF;

  WITH l AS (
    SELECT * FROM jsonb_to_recordset(v_all) AS x(item int, codigo_rubro int, concepto text, unidad_negocio text,
           origen text, tarifa numeric, cantidad numeric, unidad text, opcional boolean, incluido boolean)
  ),
  aj AS (
    SELECT l.*,
      CASE WHEN coalesce(p_ajustes->'excluir', '[]') @> to_jsonb(l.item) THEN false
           WHEN coalesce(p_ajustes->'incluir', '[]') @> to_jsonb(l.item) THEN true
           ELSE l.incluido END AS va,
      CASE WHEN l.opcional AND p_ajustes->'cantidades' ? l.item::text
           THEN (p_ajustes->'cantidades'->>l.item::text)::numeric ELSE l.cantidad END AS cant
    FROM l
  ),
  fin AS (
    SELECT aj.*, round(aj.tarifa * aj.cant, 2) AS neto,
           row_number() OVER (ORDER BY aj.item) AS n
    FROM aj WHERE aj.va AND aj.cant > 0
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'item', n, 'rubro', codigo_rubro, 'concepto', concepto, 'unidad_negocio', unidad_negocio,
           'origen', origen, 'tarifa', tarifa, 'cantidad', cant, 'unidad', unidad,
           'neto', neto, 'igv', round(neto * v_igv, 2), 'total', neto + round(neto * v_igv, 2))
           ORDER BY n), '[]'::jsonb)
  INTO v_lineas FROM fin;

  SELECT coalesce(jsonb_agg(jsonb_build_object('fecha', m.fecha, 'operacion', m.operacion,
           'cuadrilla', m.cuadrilla, 'montacarga', m.montacarga OR m.montacarga_5tm, 'manipuleo', m.manipuleo,
           'observaciones', m.observaciones) ORDER BY m.fecha), '[]'::jsonb)
  INTO v_mov FROM ops.movilizacion m
  WHERE m.contenedor = c.contenedor AND m.fecha BETWEEN c.fecha_ingreso_balanza AND p_fecha_retiro;

  -- Alertas para el ejecutivo
  IF NOT core.iso6346_valido(c.contenedor) THEN
    v_alertas := v_alertas || jsonb_build_object('nivel','alto','mensaje','El número de contenedor no pasa el dígito de control ISO 6346');
  END IF;
  IF c.mercaderia = 'SIMULADO' THEN
    v_alertas := v_alertas || jsonb_build_object('nivel','alto','mensaje','Datos del DT simulados para prueba (puerto, tipo e ingreso supuestos)');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_lineas) x WHERE x->>'rubro' IS NULL AND x->>'origen' <> 'SERV_ADICIONAL') THEN
    v_alertas := v_alertas || jsonb_build_object('nivel','medio','mensaje','Hay conceptos sin código de rubro de facturación');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_all) x WHERE x->>'origen' = 'SERV_ADICIONAL') THEN
    v_alertas := v_alertas || jsonb_build_object('nivel','medio','mensaje','Incluye facturación del puerto trasladada al cliente (Servicios adicionales)');
  END IF;
  IF v_fac->>'ruc' IS NULL THEN
    v_alertas := v_alertas || jsonb_build_object('nivel','alto','mensaje','Falta el RUC de ' || coalesce(v_fac->>'razon_social','el cliente') || ' (a quien se factura): complétalo en la data del DT');
  END IF;
  IF v_ac.tipo = 'AGENCIA' THEN
    v_alertas := v_alertas || jsonb_build_object('nivel','info','mensaje','Tarifario del acuerdo con la agencia ' || v_cli.nombre_corto || '; se factura al cliente ' || coalesce(v_fac->>'razon_social',''));
  END IF;
  IF (p_fecha_retiro - c.fecha_ingreso_balanza) > v_tar.dias_libres THEN
    v_alertas := v_alertas || jsonb_build_object('nivel','medio','mensaje',
      format('%s días en depósito: supera los %s días libres, se cobran %s días de almacenaje',
             p_fecha_retiro - c.fecha_ingreso_balanza, v_tar.dias_libres, (p_fecha_retiro - c.fecha_ingreso_balanza) - v_tar.dias_libres));
  END IF;
  v_alertas := v_alertas || coalesce((
    SELECT jsonb_agg(DISTINCT jsonb_build_object('nivel','info','mensaje', (x->>'concepto') || ': ' || (x->>'nota')))
    FROM jsonb_array_elements(v_all) x
    WHERE x->>'nota' IS NOT NULL AND x->>'origen' <> 'SERV_ADICIONAL' AND (x->>'incluido')::boolean), '[]'::jsonb);

  RETURN jsonb_build_object(
    'version_formato', 1,
    'emisor', jsonb_build_object('empresa', 'DEPOSITO TEMPORAL DEMO S.A.C.', 'sede', 'CALLAO'),
    'cliente', v_fac,
    'acuerdo', jsonb_build_object('tipo', v_ac.tipo, 'ruc', v_cli.ruc, 'razon_social', v_cli.razon_social, 'nombre', v_cli.nombre_corto),
    'tarifario', jsonb_build_object('codigo', v_tar.codigo, 'vigente_desde', v_tar.vigente_desde),
    'servicio', jsonb_build_object(
        'bl', c.bk, 'contenedor', c.contenedor, 'tipo_servicio', c.tipo_servicio,
        'tamano', c.tamano_cnt, 'clase', c.clase_cnt, 'isotype', c.isotype,
        'tipo_carga', c.tipo_carga, 'clase_imo', c.clase_imo, 'operador_portuario', c.operador_portuario,
        'conexion_reefer', c.conexion, 'linea_naviera', c.linea_maritima, 'agencia_aduana', c.agencia_aduana,
        'fecha_ingreso', c.fecha_ingreso_balanza, 'fecha_retiro', p_fecha_retiro,
        'dias_en_deposito', p_fecha_retiro - c.fecha_ingreso_balanza),
    'movilizaciones', v_mov,
    'moneda', 'USD',
    'igv_tasa', v_igv,
    'lineas', v_lineas,
    'totales', jsonb_build_object(
        'neto',  coalesce((SELECT sum((x->>'neto')::numeric)  FROM jsonb_array_elements(v_lineas) x), 0),
        'igv',   coalesce((SELECT sum((x->>'igv')::numeric)   FROM jsonb_array_elements(v_lineas) x), 0),
        'total', coalesce((SELECT sum((x->>'total')::numeric) FROM jsonb_array_elements(v_lineas) x), 0)),
    'totales_por_unidad', coalesce((SELECT jsonb_object_agg(un, t) FROM (
        SELECT x->>'unidad_negocio' un, sum((x->>'total')::numeric) t FROM jsonb_array_elements(v_lineas) x GROUP BY 1) q), '{}'::jsonb),
    'alertas', v_alertas
  );
END $$;


--
-- Name: emitir(text, date, text, jsonb, text, text); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.emitir(p_contenedor text, p_fecha_retiro date, p_bl text DEFAULT NULL::text, p_ajustes jsonb DEFAULT '{}'::jsonb, p_usuario text DEFAULT NULL::text, p_origen text DEFAULT 'REAL'::text) RETURNS TABLE(liquidacion_id bigint, version integer, reemplazo_id bigint)
    LANGUAGE plpgsql
    AS $$
#variable_conflict use_column
DECLARE
  v_json   jsonb;
  v_prev   liq.liquidacion;
  v_ver    int;
  v_id     bigint;
  v_cli    int;
  v_tar    int;
BEGIN
  v_json := liq.cotizar_json(p_contenedor, p_fecha_retiro, p_bl, p_ajustes);
  IF jsonb_array_length(v_json->'lineas') = 0 THEN
    RAISE EXCEPTION 'La liquidación no tiene líneas';
  END IF;

  SELECT * INTO v_prev FROM liq.liquidacion l
  WHERE l.bl = v_json#>>'{servicio,bl}' AND l.contenedor = v_json#>>'{servicio,contenedor}'
    AND l.estado IN ('EMITIDA','FACTURADA')
  FOR UPDATE;
  IF v_prev.estado = 'FACTURADA' THEN
    RAISE EXCEPTION 'El contenedor % del BL % ya fue facturado (factura %). Anule primero si corresponde.',
      v_prev.contenedor, v_prev.bl, v_prev.factura_numero;
  END IF;
  IF v_prev.id IS NOT NULL THEN
    UPDATE liq.liquidacion SET estado = 'REEMPLAZADA' WHERE id = v_prev.id;
  END IF;

  SELECT coalesce(max(l.version), 0) + 1 INTO v_ver FROM liq.liquidacion l
  WHERE l.bl = v_json#>>'{servicio,bl}' AND l.contenedor = v_json#>>'{servicio,contenedor}';

  SELECT t.cliente_id INTO v_cli FROM tarifas.tarifario t WHERE t.codigo = v_json#>>'{tarifario,codigo}';
  SELECT t.id INTO v_tar FROM tarifas.tarifario t WHERE t.codigo = v_json#>>'{tarifario,codigo}';

  v_json := v_json || jsonb_build_object('liquidacion', jsonb_build_object(
              'version', v_ver, 'emitido_por', p_usuario, 'emitido_en', now(), 'origen', p_origen));

  INSERT INTO liq.liquidacion (facturar_ruc, facturar_razon, cliente_id, tarifario_id, bl, contenedor, fecha_retiro, version, estado, origen,
                               neto, igv, total, json, hash, emitido_por)
  VALUES ((v_json#>>'{cliente,ruc}')::bigint, v_json#>>'{cliente,razon_social}', v_cli, v_tar, v_json#>>'{servicio,bl}', v_json#>>'{servicio,contenedor}', p_fecha_retiro, v_ver, 'EMITIDA',
          p_origen, (v_json#>>'{totales,neto}')::numeric, (v_json#>>'{totales,igv}')::numeric,
          (v_json#>>'{totales,total}')::numeric, v_json,
          encode(sha256(convert_to(v_json::text, 'UTF8')), 'hex'), p_usuario)
  RETURNING id INTO v_id;

  -- El JSON guardado lleva su propio número de liquidación
  UPDATE liq.liquidacion SET json = json || jsonb_build_object('liquidacion',
           (json->'liquidacion') || jsonb_build_object('id', v_id, 'codigo', 'LQ-' || lpad(v_id::text, 6, '0')))
  WHERE id = v_id;

  INSERT INTO liq.liquidacion_linea (liquidacion_id, item, codigo_rubro, concepto, unidad_negocio, origen,
                                     tarifa, cantidad, neto, igv, total)
  SELECT v_id, (x->>'item')::int, (x->>'rubro')::int, x->>'concepto', x->>'unidad_negocio', x->>'origen',
         (x->>'tarifa')::numeric, (x->>'cantidad')::numeric, (x->>'neto')::numeric,
         (x->>'igv')::numeric, (x->>'total')::numeric
  FROM jsonb_array_elements(v_json->'lineas') x;

  RETURN QUERY SELECT v_id, v_ver, v_prev.id;
END $$;


--
-- Name: guardar(jsonb, date, text, text, text); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.guardar(p_json jsonb, p_fecha date, p_tipo text, p_usuario text DEFAULT NULL::text, p_origen text DEFAULT 'REAL'::text) RETURNS TABLE(liquidacion_id bigint, version integer, reemplazo_id bigint)
    LANGUAGE plpgsql
    AS $$
#variable_conflict use_column
DECLARE
  v_json jsonb := p_json;
  v_bl   text := p_json#>>'{servicio,bl}';
  v_cnt  text := p_json#>>'{servicio,contenedor}';
  v_prev liq.liquidacion;
  v_ver  int;
  v_id   bigint;
BEGIN
  IF jsonb_array_length(v_json->'lineas') = 0 THEN RAISE EXCEPTION 'La liquidación no tiene líneas'; END IF;
  SELECT * INTO v_prev FROM liq.liquidacion l
  WHERE l.bl = v_bl AND l.contenedor = v_cnt AND l.estado IN ('EMITIDA','FACTURADA') FOR UPDATE;
  IF v_prev.estado = 'FACTURADA' THEN
    RAISE EXCEPTION '% ya fue facturado (factura %). Anule primero si corresponde.', v_bl, v_prev.factura_numero;
  END IF;
  IF v_prev.id IS NOT NULL THEN UPDATE liq.liquidacion SET estado = 'REEMPLAZADA' WHERE id = v_prev.id; END IF;
  SELECT coalesce(max(l.version), 0) + 1 INTO v_ver FROM liq.liquidacion l WHERE l.bl = v_bl AND l.contenedor = v_cnt;

  v_json := v_json || jsonb_build_object('liquidacion', jsonb_build_object(
              'version', v_ver, 'emitido_por', p_usuario, 'emitido_en', now(), 'origen', p_origen));
  INSERT INTO liq.liquidacion (cliente_id, tarifario_id, bl, contenedor, fecha_retiro, version, estado, origen, tipo,
                               neto, igv, total, json, hash, emitido_por)
  VALUES ((SELECT id FROM core.cliente WHERE ruc = (v_json#>>'{cliente,ruc}')::bigint),
          (SELECT id FROM tarifas.tarifario WHERE codigo = v_json#>>'{tarifario,codigo}'),
          v_bl, v_cnt, p_fecha, v_ver, 'EMITIDA', p_origen, p_tipo,
          (v_json#>>'{totales,neto}')::numeric, (v_json#>>'{totales,igv}')::numeric, (v_json#>>'{totales,total}')::numeric,
          v_json, encode(sha256(convert_to(v_json::text, 'UTF8')), 'hex'), p_usuario)
  RETURNING id INTO v_id;
  UPDATE liq.liquidacion SET json = json || jsonb_build_object('liquidacion',
           (json->'liquidacion') || jsonb_build_object('id', v_id, 'codigo', 'LQ-' || lpad(v_id::text, 6, '0')))
  WHERE id = v_id;
  INSERT INTO liq.liquidacion_linea (liquidacion_id, item, codigo_rubro, concepto, unidad_negocio, origen,
                                     tarifa, cantidad, neto, igv, total)
  SELECT v_id, (x->>'item')::int, (x->>'rubro')::int, x->>'concepto', x->>'unidad_negocio', x->>'origen',
         (x->>'tarifa')::numeric, (x->>'cantidad')::numeric, (x->>'neto')::numeric, (x->>'igv')::numeric, (x->>'total')::numeric
  FROM jsonb_array_elements(v_json->'lineas') x;
  RETURN QUERY SELECT v_id, v_ver, v_prev.id;
END $$;


--
-- Name: marcar_facturada(bigint, text, text); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.marcar_facturada(p_id bigint, p_factura text, p_usuario text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF coalesce(trim(p_factura), '') = '' THEN RAISE EXCEPTION 'Indique el número de factura'; END IF;
  UPDATE liq.liquidacion SET estado = 'FACTURADA', factura_numero = upper(trim(p_factura)),
         facturado_por = p_usuario, facturado_en = now()
  WHERE id = p_id AND estado = 'EMITIDA';
  IF NOT FOUND THEN RAISE EXCEPTION 'La liquidación % no está pendiente de facturar', p_id; END IF;
END $$;


--
-- Name: totales(jsonb); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.totales(p_lineas jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT jsonb_build_object(
    'neto',  coalesce(sum((x->>'neto')::numeric), 0),
    'igv',   coalesce(sum((x->>'igv')::numeric), 0),
    'total', coalesce(sum((x->>'total')::numeric), 0))
  FROM jsonb_array_elements(p_lineas) x
$$;


--
-- Name: totales_por_unidad(jsonb); Type: FUNCTION; Schema: liq; Owner: -
--

CREATE FUNCTION liq.totales_por_unidad(p_lineas jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT coalesce(jsonb_object_agg(un, t), '{}'::jsonb) FROM (
    SELECT x->>'unidad_negocio' un, sum((x->>'total')::numeric) t FROM jsonb_array_elements(p_lineas) x GROUP BY 1) q
$$;


--
-- Name: procesar_dt(integer); Type: FUNCTION; Schema: ops; Owner: -
--

CREATE FUNCTION ops.procesar_dt(p_importacion integer) RETURNS TABLE(aceptadas integer, rechazadas integer)
    LANGUAGE plpgsql
    AS $_$
DECLARE r record; v_ok int := 0; v_bad int := 0; v_det jsonb := '[]'; rec dt.contenedor; v_falt text[];
BEGIN
  FOR r IN SELECT f.fila, (SELECT jsonb_object_agg(lower(regexp_replace(trim(k), '\s+', '_', 'g')), nullif(trim(v), ''))
                           FROM jsonb_each_text(f.datos) e(k, v)) AS d
           FROM ops.importacion_fila f WHERE f.importacion_id = p_importacion ORDER BY f.fila
  LOOP
    IF upper(coalesce(r.d->>'contenedor','')) !~ '^[A-Z]{4}\d{7}$' THEN
      v_bad := v_bad + 1;
      v_det := v_det || jsonb_build_object('fila', r.fila, 'motivo', 'No es un número de contenedor: ' || coalesce(r.d->>'contenedor','vacío'));
      CONTINUE;
    END IF;
    v_falt := dt.campos_faltantes(r.d);
    IF cardinality(v_falt) > 0 THEN
      -- no pisa un contenedor que ya está completo
      IF NOT EXISTS (SELECT 1 FROM dt.contenedor c WHERE c.contenedor = upper(trim(r.d->>'contenedor')) AND c.bk = upper(trim(r.d->>'bk'))) THEN
        INSERT INTO dt.contenedor_pendiente (tipo_servicio, bk, contenedor, cliente, faltan, datos)
        VALUES (coalesce(upper(r.d->>'tipo_servicio'),'IMPO'), upper(trim(r.d->>'bk')), upper(trim(r.d->>'contenedor')), r.d->>'cliente', v_falt, r.d)
        ON CONFLICT (tipo_servicio, bk, contenedor) DO UPDATE SET faltan = EXCLUDED.faltan, datos = EXCLUDED.datos, actualizado_en = now();
      END IF;
      v_bad := v_bad + 1;
      IF v_bad <= 500 THEN v_det := v_det || jsonb_build_object('fila', r.fila, 'motivo',
        upper(r.d->>'contenedor') || ': falta ' || array_to_string(v_falt, ', ')); END IF;
      CONTINUE;
    END IF;
    BEGIN
      rec := jsonb_populate_record(NULL::dt.contenedor,
               jsonb_build_object('hora_ingreso_balanza','00:00','condicion_cnt','FCL','tipo_servicio','IMPO')
               || jsonb_strip_nulls(r.d)
               || jsonb_build_object('fecha_ingreso_balanza', core.to_fecha(r.d->>'fecha_ingreso_balanza'),
                                     'contenedor', upper(trim(r.d->>'contenedor')), 'bk', upper(trim(r.d->>'bk')),
                                     'conexion', coalesce(lower(r.d->>'conexion') IN ('true','t','1','si','sí','verdadero'), false),
                                     'tipo_carga', upper(r.d->>'tipo_carga'), 'clase_cnt', upper(r.d->>'clase_cnt'),
                                     'operador_portuario', upper(r.d->>'operador_portuario')));
      INSERT INTO dt.contenedor SELECT rec.*
      ON CONFLICT (tipo_servicio, bk, contenedor) DO UPDATE SET
        clase_cnt = EXCLUDED.clase_cnt, tamano_cnt = EXCLUDED.tamano_cnt, isotype = EXCLUDED.isotype,
        tipo_carga = EXCLUDED.tipo_carga, clase_imo = EXCLUDED.clase_imo, fecha_ingreso_balanza = EXCLUDED.fecha_ingreso_balanza,
        hora_ingreso_balanza = EXCLUDED.hora_ingreso_balanza,
        cliente = EXCLUDED.cliente, ruc_cliente = EXCLUDED.ruc_cliente, operador_portuario = EXCLUDED.operador_portuario,
        conexion = EXCLUDED.conexion, temperatura = EXCLUDED.temperatura, linea_maritima = EXCLUDED.linea_maritima,
        agencia_aduana = EXCLUDED.agencia_aduana, mercaderia = EXCLUDED.mercaderia;
      DELETE FROM dt.contenedor_pendiente p WHERE p.contenedor = rec.contenedor AND p.bk = rec.bk;
      v_ok := v_ok + 1;
    EXCEPTION WHEN others THEN
      v_bad := v_bad + 1;
      IF v_bad <= 500 THEN v_det := v_det || jsonb_build_object('fila', r.fila, 'motivo', upper(r.d->>'contenedor') || ': ' || SQLERRM); END IF;
    END;
  END LOOP;
  UPDATE ops.importacion SET aceptadas = v_ok, rechazadas = v_bad, detalle = v_det WHERE id = p_importacion;
  RETURN QUERY SELECT v_ok, v_bad;
END $_$;


--
-- Name: procesar_movilizaciones(integer); Type: FUNCTION; Schema: ops; Owner: -
--

CREATE FUNCTION ops.procesar_movilizaciones(p_importacion integer) RETURNS TABLE(aceptadas integer, rechazadas integer)
    LANGUAGE plpgsql
    AS $_$
DECLARE v_ok int; v_bad int; v_det jsonb;
BEGIN
  CREATE TEMP TABLE _m ON COMMIT DROP AS
  SELECT f.fila,
         core.to_fecha(f.datos->>'FECHA')                         AS fecha,
         core.norm(f.datos->>'REGIMEN')                           AS regimen,
         core.norm(coalesce(f.datos->>'tien', f.datos->>'AGENCIA')) AS agencia,
         core.norm(f.datos->>'TIPO')                              AS tipo_raw,
         upper(regexp_replace(coalesce(f.datos->>'CTN',''), '\s', '', 'g')) AS contenedor,
         core.norm(f.datos->>'OPERACION')                         AS operacion,
         core.norm(f.datos->>'BL/BK')                             AS bl,
         core.norm(f.datos->>'ORDEN DE TRABAJO')                  AS orden_trabajo,
         core.norm(f.datos->>'CLIENTE')                           AS cliente,
         core.norm(f.datos->>'MONTACARGA')                        AS col_montacarga,
         core.norm(f.datos->>'MONTACARGA 5TM')                    AS col_montacarga5,
         core.norm(f.datos->>'CUADRILLA')                         AS col_cuadrilla,
         core.norm(f.datos->>'ANTECAMARA')                        AS col_antecamara,
         core.norm(f.datos->>'OBSERVACIONES')                     AS observaciones,
         core.norm(f.datos->>'EJECUTIVO')                         AS ejecutivo
  FROM ops.importacion_fila f
  WHERE f.importacion_id = p_importacion;

  SELECT coalesce(jsonb_agg(jsonb_build_object('fila', fila, 'motivo',
           CASE WHEN fecha IS NULL THEN 'Fecha no reconocida'
                ELSE 'No es un número de contenedor (' || coalesce(contenedor,'vacío') || ')' END)
           ORDER BY fila) FILTER (WHERE fila IS NOT NULL), '[]'::jsonb)
  INTO v_det
  FROM (SELECT * FROM _m WHERE fecha IS NULL OR contenedor !~ '^[A-Z]{4}\d{7}$' LIMIT 500) x;

  DELETE FROM ops.movilizacion;

  INSERT INTO ops.movilizacion (importacion_id, fila, fecha, regimen, agencia, tipo_raw, tamano, contenedor,
         contenedor_valido, operacion, aforo, senasa, bl, orden_trabajo, cliente, cuadrilla, montacarga,
         montacarga_5tm, antecamara, manipuleo, observaciones, ejecutivo)
  SELECT p_importacion, fila, fecha, regimen, agencia, tipo_raw,
         nullif(substring(tipo_raw from '(20|40|45)'), '')::smallint,
         contenedor, core.iso6346_valido(contenedor), operacion,
         coalesce(operacion LIKE '%AFORO%', false),
         coalesce(operacion LIKE '%SENASA%', false),
         bl, orden_trabajo, cliente,
         col_cuadrilla IS NOT NULL OR coalesce(observaciones LIKE '%CUADRILLA%', false),
         col_montacarga IS NOT NULL OR coalesce(observaciones LIKE '%MONTACARGA%', false),
         col_montacarga5 IS NOT NULL,
         col_antecamara IS NOT NULL,
         coalesce(observaciones ~ '(MANIPULEO|MANIP\.|POSIC)', false),
         observaciones, ejecutivo
  FROM _m
  WHERE fecha IS NOT NULL AND contenedor ~ '^[A-Z]{4}\d{7}$';
  GET DIAGNOSTICS v_ok = ROW_COUNT;

  SELECT count(*) - v_ok INTO v_bad FROM _m;
  UPDATE ops.importacion SET aceptadas = v_ok, rechazadas = v_bad, detalle = v_det WHERE id = p_importacion;
  RETURN QUERY SELECT v_ok, v_bad;
END $_$;


--
-- Name: procesar_programacion(integer, integer); Type: FUNCTION; Schema: ops; Owner: -
--

CREATE FUNCTION ops.procesar_programacion(p_importacion integer, p_cliente integer) RETURNS TABLE(aceptadas integer, rechazadas integer)
    LANGUAGE plpgsql
    AS $_$
DECLARE v_ok int; v_bad int; v_det jsonb;
BEGIN
  CREATE TEMP TABLE _p ON COMMIT DROP AS
  SELECT f.fila, f.datos d,
         CASE WHEN (f.datos->>'SEM') ~ '^\d+$' THEN (f.datos->>'SEM')::int END AS semana,
         upper(regexp_replace(coalesce(f.datos->>'CONTAINER', f.datos->>'CONTENEDOR', ''), '\s', '', 'g')) AS contenedor
  FROM ops.importacion_fila f WHERE f.importacion_id = p_importacion;

  SELECT coalesce(jsonb_agg(jsonb_build_object('fila', fila, 'motivo',
           'No es un contenedor (' || coalesce(nullif(contenedor,''),'vacío') || '), p. ej. carga suelta o inmovilizada') ORDER BY fila), '[]'::jsonb)
  INTO v_det FROM (SELECT * FROM _p WHERE contenedor !~ '^[A-Z]{4}\d{7}$' LIMIT 500) x;

  DELETE FROM ops.programacion WHERE cliente_id = p_cliente;

  INSERT INTO ops.programacion (importacion_id, fila, cliente_id, semana, agencia, regimen, bl, contenedor, ap_reference,
         shipment, fecha_retiro, fecha_devolucion, dam, almacen, cita, aforo, linea, depot, observaciones)
  SELECT p_importacion, fila, p_cliente, semana, core.norm(d->>'AGENCIA'), core.norm(d->>'REG'), core.norm(d->>'BL'),
         contenedor, core.norm(d->>'AP REFERENCE'), core.norm(d->>'SHIPMENT'),
         core.to_fecha_semana(d->>'RETIRO', semana), core.to_fecha_semana(d->>'DEVOLUCIÓN VACÍO', semana),
         core.norm(d->>'DAM'), core.norm(coalesce(d->>'Columna1', d->>'ALMACEN')), core.norm(d->>'CITA'),
         core.norm(d->>'AFORO'), core.norm(d->>'LINEA'), core.norm(d->>'DEPOT'), core.norm(d->>'OBSERVACIONES')
  FROM _p WHERE contenedor ~ '^[A-Z]{4}\d{7}$';
  GET DIAGNOSTICS v_ok = ROW_COUNT;

  SELECT count(*) - v_ok INTO v_bad FROM _p;
  UPDATE ops.importacion SET aceptadas = v_ok, rechazadas = v_bad, detalle = v_det WHERE id = p_importacion;
  RETURN QUERY SELECT v_ok, v_bad;
END $_$;


--
-- Name: procesar_servicios_adicionales(integer); Type: FUNCTION; Schema: ops; Owner: -
--

CREATE FUNCTION ops.procesar_servicios_adicionales(p_importacion integer) RETURNS TABLE(aceptadas integer, rechazadas integer)
    LANGUAGE plpgsql
    AS $_$
DECLARE v_ok int; v_bad int; v_det jsonb;
BEGIN
  CREATE TEMP TABLE _s ON COMMIT DROP AS
  SELECT f.fila, d,
         upper(regexp_replace(coalesce(d->>'Contenedor',''), '\s', '', 'g')) AS contenedor,
         core.norm(d->>'CONCEPTO') AS concepto
  FROM ops.importacion_fila f, LATERAL (SELECT f.datos AS d) x
  WHERE f.importacion_id = p_importacion;

  SELECT coalesce(jsonb_agg(jsonb_build_object('fila', fila, 'motivo', 'Sin concepto') ORDER BY fila), '[]'::jsonb)
  INTO v_det FROM (SELECT fila FROM _s WHERE concepto IS NULL LIMIT 500) x;

  DELETE FROM ops.servicio_adicional;

  INSERT INTO ops.servicio_adicional (importacion_id, fila, gkey, contenedor, fecha_desde, fecha_hasta, fecha_recepcion,
         concepto, descripcion, cantidad, tarifa, monto, moneda, monto_usd, proveedor, regimen, bl, bl_master,
         factura_proveedor, cliente, cliente_facturar, ejecutivo, status_ops, area)
  SELECT p_importacion, fila, d->>'Gkey',
         CASE WHEN contenedor ~ '^[A-Z]{4}\d{7}$' THEN contenedor END,
         core.to_fecha(d->>'Fecha Desde'), core.to_fecha(d->>'Fecha Hasta'), core.to_fecha(d->>'FECHA_RECEPCION'),
         concepto, d->>'Descripción',
         core.to_num(d->>'Cantidad días'), core.to_num(d->>'TARIFA'), core.to_num(d->>'IT Monto'),
         core.norm(d->>'MONEDA'),
         coalesce(core.to_num(d->>'Monto USD'), core.to_num(d->>' Monto USD '),
                  CASE WHEN core.norm(d->>'MONEDA') = 'USD' THEN core.to_num(d->>'IT Monto') END),
         core.norm(d->>'PROVEEDOR'), core.norm(d->>'Régimen'),
         core.norm(d->>'BOOKING_BL'), core.norm(d->>'BL Master'), core.norm(d->>'FACTURA PROVEEDOR'),
         core.norm(d->>'CLIENTE'), core.norm(d->>'CLIENTE FACTURAR'), core.norm(d->>'EJECUTIVO'),
         core.norm(d->>'STATUS OPS'), core.norm(d->>'ÁREA')
  FROM _s
  WHERE concepto IS NOT NULL;
  GET DIAGNOSTICS v_ok = ROW_COUNT;

  SELECT count(*) - v_ok INTO v_bad FROM _s;
  UPDATE ops.importacion SET aceptadas = v_ok, rechazadas = v_bad, detalle = v_det WHERE id = p_importacion;
  RETURN QUERY SELECT v_ok, v_bad;
END $_$;


--
-- Name: cliente_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.cliente_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cliente_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.cliente_id_seq OWNED BY core.cliente.id;


--
-- Name: parametro; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.parametro (
    clave text NOT NULL,
    valor numeric NOT NULL,
    descripcion text
);


--
-- Name: carga_id_seq; Type: SEQUENCE; Schema: cs; Owner: -
--

CREATE SEQUENCE cs.carga_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: carga_id_seq; Type: SEQUENCE OWNED BY; Schema: cs; Owner: -
--

ALTER SEQUENCE cs.carga_id_seq OWNED BY cs.carga.id;


--
-- Name: evento; Type: TABLE; Schema: cs; Owner: -
--

CREATE TABLE cs.evento (
    id bigint NOT NULL,
    carga_id integer NOT NULL,
    tipo text NOT NULL,
    detalle jsonb,
    usuario text,
    en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT evento_tipo_check CHECK ((tipo = ANY (ARRAY['INGRESO'::text, 'SALIDA'::text, 'CAMBIO'::text, 'SALIDA_REVERTIDA'::text])))
);


--
-- Name: evento_id_seq; Type: SEQUENCE; Schema: cs; Owner: -
--

CREATE SEQUENCE cs.evento_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: evento_id_seq; Type: SEQUENCE OWNED BY; Schema: cs; Owner: -
--

ALTER SEQUENCE cs.evento_id_seq OWNED BY cs.evento.id;


--
-- Name: liquidacion; Type: TABLE; Schema: liq; Owner: -
--

CREATE TABLE liq.liquidacion (
    id bigint NOT NULL,
    cliente_id integer NOT NULL,
    tarifario_id integer NOT NULL,
    bl text NOT NULL,
    contenedor text NOT NULL,
    fecha_retiro date NOT NULL,
    version integer NOT NULL,
    estado text NOT NULL,
    origen text DEFAULT 'REAL'::text NOT NULL,
    neto numeric(12,2) NOT NULL,
    igv numeric(12,2) NOT NULL,
    total numeric(12,2) NOT NULL,
    json jsonb NOT NULL,
    hash text NOT NULL,
    emitido_por text,
    emitido_en timestamp with time zone DEFAULT now() NOT NULL,
    factura_numero text,
    facturado_por text,
    facturado_en timestamp with time zone,
    anulado_motivo text,
    anulado_en timestamp with time zone,
    tipo text DEFAULT 'FCL'::text NOT NULL,
    facturar_ruc bigint,
    facturar_razon text,
    CONSTRAINT liquidacion_estado_check CHECK ((estado = ANY (ARRAY['EMITIDA'::text, 'FACTURADA'::text, 'REEMPLAZADA'::text, 'ANULADA'::text]))),
    CONSTRAINT liquidacion_origen_check CHECK ((origen = ANY (ARRAY['REAL'::text, 'PRUEBA'::text]))),
    CONSTRAINT liquidacion_tipo_check CHECK ((tipo = ANY (ARRAY['FCL'::text, 'CS_MENSUAL'::text, 'CS_DEPOSITO'::text]))),
    CONSTRAINT liquidacion_version_check CHECK ((version >= 1))
);


--
-- Name: v_carga; Type: VIEW; Schema: cs; Owner: -
--

CREATE VIEW cs.v_carga AS
 SELECT c.id,
    c.cliente_id,
    c.bl,
    c.modalidad,
    c.cobra_almacenaje,
    c.nave,
    c.orden_servicio,
    c.bultos,
    c.unidad_bulto,
    c.peso_kg,
    c.m2,
    c.ubicacion,
    c.fecha_ingreso,
    c.horas_montacarga,
    c.horas_cuadrilla,
    c.observacion,
    c.fecha_salida,
    c.motivo_salida,
    c.detalle_salida,
    c.creado_por,
    c.creado_en,
    cl.ruc,
    cl.nombre_corto AS cliente,
        CASE
            WHEN (c.fecha_ingreso IS NOT NULL) THEN (COALESCE(c.fecha_salida, CURRENT_DATE) - c.fecha_ingreso)
            ELSE NULL::integer
        END AS dias,
    ( SELECT jsonb_build_object('id', l.id, 'estado', l.estado, 'total', l.total) AS jsonb_build_object
           FROM liq.liquidacion l
          WHERE ((l.tipo = 'CS_DEPOSITO'::text) AND (l.bl = c.bl) AND (l.estado = ANY (ARRAY['EMITIDA'::text, 'FACTURADA'::text])))
          ORDER BY l.id DESC
         LIMIT 1) AS liquidacion
   FROM (cs.carga c
     JOIN core.cliente cl ON ((cl.id = c.cliente_id)));


--
-- Name: contenedor_pendiente; Type: TABLE; Schema: dt; Owner: -
--

CREATE TABLE dt.contenedor_pendiente (
    tipo_servicio text DEFAULT 'IMPO'::text NOT NULL,
    bk text NOT NULL,
    contenedor text NOT NULL,
    cliente text,
    faltan text[] NOT NULL,
    datos jsonb,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: isotype_catalogo; Type: TABLE; Schema: dt; Owner: -
--

CREATE TABLE dt.isotype_catalogo (
    isotype character varying NOT NULL,
    tamano_cnt smallint NOT NULL,
    clase_cnt character varying NOT NULL
);


--
-- Name: liquidacion_id_seq; Type: SEQUENCE; Schema: liq; Owner: -
--

CREATE SEQUENCE liq.liquidacion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: liquidacion_id_seq; Type: SEQUENCE OWNED BY; Schema: liq; Owner: -
--

ALTER SEQUENCE liq.liquidacion_id_seq OWNED BY liq.liquidacion.id;


--
-- Name: liquidacion_linea; Type: TABLE; Schema: liq; Owner: -
--

CREATE TABLE liq.liquidacion_linea (
    liquidacion_id bigint NOT NULL,
    item integer NOT NULL,
    codigo_rubro integer,
    concepto text NOT NULL,
    unidad_negocio text NOT NULL,
    origen text NOT NULL,
    tarifa numeric(12,2) NOT NULL,
    cantidad numeric(12,2) NOT NULL,
    neto numeric(12,2) NOT NULL,
    igv numeric(12,2) NOT NULL,
    total numeric(12,2) NOT NULL
);


--
-- Name: v_contenedor_pendiente; Type: VIEW; Schema: liq; Owner: -
--

CREATE VIEW liq.v_contenedor_pendiente AS
 SELECT bk AS bl,
    contenedor,
    cliente,
    ruc_cliente,
    tamano_cnt,
    clase_cnt,
    tipo_carga,
    operador_portuario,
    fecha_ingreso_balanza,
    (CURRENT_DATE - fecha_ingreso_balanza) AS dias_en_deposito
   FROM dt.contenedor c
  WHERE (((tipo_servicio)::text = 'IMPO'::text) AND (NOT (EXISTS ( SELECT 1
           FROM liq.liquidacion l
          WHERE ((l.bl = (c.bk)::text) AND (l.contenedor = (c.contenedor)::text) AND (l.estado = ANY (ARRAY['EMITIDA'::text, 'FACTURADA'::text])))))));


--
-- Name: importacion; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.importacion (
    id integer NOT NULL,
    tipo text NOT NULL,
    archivo text,
    filas integer DEFAULT 0 NOT NULL,
    aceptadas integer DEFAULT 0 NOT NULL,
    rechazadas integer DEFAULT 0 NOT NULL,
    detalle jsonb DEFAULT '[]'::jsonb NOT NULL,
    creado_por text,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT importacion_tipo_check CHECK ((tipo = ANY (ARRAY['MOVILIZACIONES'::text, 'SERV_ADICIONALES'::text, 'PROGRAMACION'::text, 'DT'::text])))
);


--
-- Name: importacion_fila; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.importacion_fila (
    importacion_id integer NOT NULL,
    fila integer NOT NULL,
    datos jsonb NOT NULL
);


--
-- Name: importacion_id_seq; Type: SEQUENCE; Schema: ops; Owner: -
--

CREATE SEQUENCE ops.importacion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: importacion_id_seq; Type: SEQUENCE OWNED BY; Schema: ops; Owner: -
--

ALTER SEQUENCE ops.importacion_id_seq OWNED BY ops.importacion.id;


--
-- Name: movilizacion; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.movilizacion (
    id bigint NOT NULL,
    importacion_id integer,
    fila integer,
    fecha date NOT NULL,
    regimen text,
    agencia text,
    tipo_raw text,
    tamano smallint,
    contenedor text NOT NULL,
    contenedor_valido boolean NOT NULL,
    operacion text,
    aforo boolean DEFAULT false NOT NULL,
    senasa boolean DEFAULT false NOT NULL,
    bl text,
    orden_trabajo text,
    cliente text,
    cuadrilla boolean DEFAULT false NOT NULL,
    montacarga boolean DEFAULT false NOT NULL,
    montacarga_5tm boolean DEFAULT false NOT NULL,
    antecamara boolean DEFAULT false NOT NULL,
    manipuleo boolean DEFAULT false NOT NULL,
    observaciones text,
    ejecutivo text
);


--
-- Name: movilizacion_id_seq; Type: SEQUENCE; Schema: ops; Owner: -
--

CREATE SEQUENCE ops.movilizacion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: movilizacion_id_seq; Type: SEQUENCE OWNED BY; Schema: ops; Owner: -
--

ALTER SEQUENCE ops.movilizacion_id_seq OWNED BY ops.movilizacion.id;


--
-- Name: programacion; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.programacion (
    id bigint NOT NULL,
    importacion_id integer,
    fila integer,
    cliente_id integer,
    semana integer,
    agencia text,
    regimen text,
    bl text,
    contenedor text NOT NULL,
    ap_reference text,
    shipment text,
    fecha_retiro date,
    fecha_devolucion date,
    dam text,
    almacen text,
    cita text,
    aforo text,
    linea text,
    depot text,
    observaciones text
);


--
-- Name: programacion_id_seq; Type: SEQUENCE; Schema: ops; Owner: -
--

CREATE SEQUENCE ops.programacion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: programacion_id_seq; Type: SEQUENCE OWNED BY; Schema: ops; Owner: -
--

ALTER SEQUENCE ops.programacion_id_seq OWNED BY ops.programacion.id;


--
-- Name: servicio_adicional; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.servicio_adicional (
    id bigint NOT NULL,
    importacion_id integer,
    fila integer,
    gkey text,
    contenedor text,
    fecha_desde date,
    fecha_hasta date,
    fecha_recepcion date,
    concepto text,
    descripcion text,
    cantidad numeric,
    tarifa numeric,
    monto numeric,
    moneda text,
    monto_usd numeric,
    proveedor text,
    regimen text,
    bl text,
    bl_master text,
    factura_proveedor text,
    cliente text,
    cliente_facturar text,
    ejecutivo text,
    status_ops text,
    area text
);


--
-- Name: servicio_adicional_id_seq; Type: SEQUENCE; Schema: ops; Owner: -
--

CREATE SEQUENCE ops.servicio_adicional_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: servicio_adicional_id_seq; Type: SEQUENCE OWNED BY; Schema: ops; Owner: -
--

ALTER SEQUENCE ops.servicio_adicional_id_seq OWNED BY ops.servicio_adicional.id;


--
-- Name: cs_periodo; Type: TABLE; Schema: tarifas; Owner: -
--

CREATE TABLE tarifas.cs_periodo (
    tarifario_id integer NOT NULL,
    periodo integer NOT NULL,
    dia_desde integer NOT NULL,
    dia_hasta integer,
    codigo_rubro integer DEFAULT 801 NOT NULL,
    tarifa_menor numeric(12,4) NOT NULL,
    tarifa_mayor numeric(12,4) NOT NULL
);


--
-- Name: imo_clase; Type: TABLE; Schema: tarifas; Owner: -
--

CREATE TABLE tarifas.imo_clase (
    clase character varying NOT NULL,
    grupo character(1) NOT NULL,
    CONSTRAINT imo_clase_grupo_check CHECK ((grupo = ANY (ARRAY['A'::bpchar, 'B'::bpchar, 'C'::bpchar])))
);


--
-- Name: recupero_concepto; Type: TABLE; Schema: tarifas; Owner: -
--

CREATE TABLE tarifas.recupero_concepto (
    concepto text NOT NULL,
    tratamiento text NOT NULL,
    nota text,
    CONSTRAINT recupero_concepto_tratamiento_check CHECK ((tratamiento = ANY (ARRAY['CUBIERTO_TARIFA'::text, 'DISPARA_SINI'::text, 'REFACTURAR'::text, 'NO_APLICA'::text])))
);


--
-- Name: regla; Type: TABLE; Schema: tarifas; Owner: -
--

CREATE TABLE tarifas.regla (
    id integer NOT NULL,
    tarifario_id integer NOT NULL,
    codigo_rubro integer,
    concepto text NOT NULL,
    unidad_negocio text DEFAULT 'DT'::text NOT NULL,
    puerto text DEFAULT 'TODOS'::text NOT NULL,
    tipo_carga text DEFAULT 'TODOS'::text NOT NULL,
    tamano text DEFAULT 'TODOS'::text NOT NULL,
    grupo_imo character(1),
    monto numeric(12,2) NOT NULL,
    unidad text DEFAULT 'CONTENEDOR'::text NOT NULL,
    disparador text NOT NULL,
    orden integer DEFAULT 100 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    removible boolean DEFAULT false NOT NULL,
    sugerir_si text,
    pendiente text,
    origen_id integer,
    CONSTRAINT regla_disparador_check CHECK ((disparador = ANY (ARRAY['SIEMPRE'::text, 'CONEXION'::text, 'DPW'::text, 'IMO'::text, 'CUADRILLA'::text, 'MONTACARGA'::text, 'MANIPULEO'::text, 'SINI'::text, 'ALMACENAJE'::text, 'RECUPERO_ADMIN'::text, 'MANUAL'::text, 'CS_INGRESO'::text, 'CS_TRANSPORTE'::text, 'CS_MONTACARGA'::text, 'CS_CUADRILLA'::text]))),
    CONSTRAINT regla_grupo_imo_check CHECK ((grupo_imo = ANY (ARRAY['A'::bpchar, 'B'::bpchar, 'C'::bpchar]))),
    CONSTRAINT regla_monto_check CHECK ((monto >= (0)::numeric)),
    CONSTRAINT regla_puerto_check CHECK ((puerto = ANY (ARRAY['APM'::text, 'DPW'::text, 'TODOS'::text]))),
    CONSTRAINT regla_sugerir_si_check CHECK ((sugerir_si = 'DEPOT_PUERTO'::text)),
    CONSTRAINT regla_tamano_check CHECK ((tamano = ANY (ARRAY['20'::text, '40'::text, 'TODOS'::text]))),
    CONSTRAINT regla_tipo_carga_check CHECK ((tipo_carga = ANY (ARRAY['DRY'::text, 'RH'::text, 'IMO'::text, 'TODOS'::text]))),
    CONSTRAINT regla_unidad_check CHECK ((unidad = ANY (ARRAY['CONTENEDOR'::text, 'DIA'::text, 'EVENTO'::text, 'HORA'::text, 'NOCHE'::text, 'VUELTA'::text, 'BL'::text]))),
    CONSTRAINT regla_unidad_negocio_check CHECK ((unidad_negocio = ANY (ARRAY['DT'::text, 'INLAND'::text])))
);


--
-- Name: regla_id_seq; Type: SEQUENCE; Schema: tarifas; Owner: -
--

CREATE SEQUENCE tarifas.regla_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: regla_id_seq; Type: SEQUENCE OWNED BY; Schema: tarifas; Owner: -
--

ALTER SEQUENCE tarifas.regla_id_seq OWNED BY tarifas.regla.id;


--
-- Name: tarifa; Type: TABLE; Schema: tarifas; Owner: -
--

CREATE TABLE tarifas.tarifa (
    id integer NOT NULL,
    codigo_rubro integer,
    concepto character varying NOT NULL,
    puerto character varying NOT NULL,
    tipo_carga character varying NOT NULL,
    tamano character varying NOT NULL,
    grupo_imo character(1),
    monto numeric NOT NULL,
    tipo_cobro character varying NOT NULL,
    disparador character varying,
    fecha_inicio date NOT NULL
);


--
-- Name: tarifario_id_seq; Type: SEQUENCE; Schema: tarifas; Owner: -
--

CREATE SEQUENCE tarifas.tarifario_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tarifario_id_seq; Type: SEQUENCE OWNED BY; Schema: tarifas; Owner: -
--

ALTER SEQUENCE tarifas.tarifario_id_seq OWNED BY tarifas.tarifario.id;


--
-- Name: cliente id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.cliente ALTER COLUMN id SET DEFAULT nextval('core.cliente_id_seq'::regclass);


--
-- Name: carga id; Type: DEFAULT; Schema: cs; Owner: -
--

ALTER TABLE ONLY cs.carga ALTER COLUMN id SET DEFAULT nextval('cs.carga_id_seq'::regclass);


--
-- Name: evento id; Type: DEFAULT; Schema: cs; Owner: -
--

ALTER TABLE ONLY cs.evento ALTER COLUMN id SET DEFAULT nextval('cs.evento_id_seq'::regclass);


--
-- Name: liquidacion id; Type: DEFAULT; Schema: liq; Owner: -
--

ALTER TABLE ONLY liq.liquidacion ALTER COLUMN id SET DEFAULT nextval('liq.liquidacion_id_seq'::regclass);


--
-- Name: importacion id; Type: DEFAULT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.importacion ALTER COLUMN id SET DEFAULT nextval('ops.importacion_id_seq'::regclass);


--
-- Name: movilizacion id; Type: DEFAULT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.movilizacion ALTER COLUMN id SET DEFAULT nextval('ops.movilizacion_id_seq'::regclass);


--
-- Name: programacion id; Type: DEFAULT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.programacion ALTER COLUMN id SET DEFAULT nextval('ops.programacion_id_seq'::regclass);


--
-- Name: servicio_adicional id; Type: DEFAULT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.servicio_adicional ALTER COLUMN id SET DEFAULT nextval('ops.servicio_adicional_id_seq'::regclass);


--
-- Name: regla id; Type: DEFAULT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.regla ALTER COLUMN id SET DEFAULT nextval('tarifas.regla_id_seq'::regclass);


--
-- Name: tarifario id; Type: DEFAULT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.tarifario ALTER COLUMN id SET DEFAULT nextval('tarifas.tarifario_id_seq'::regclass);


--
-- Name: cliente cliente_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.cliente
    ADD CONSTRAINT cliente_pkey PRIMARY KEY (id);


--
-- Name: cliente cliente_ruc_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.cliente
    ADD CONSTRAINT cliente_ruc_key UNIQUE (ruc);


--
-- Name: parametro parametro_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.parametro
    ADD CONSTRAINT parametro_pkey PRIMARY KEY (clave);


--
-- Name: carga carga_pkey; Type: CONSTRAINT; Schema: cs; Owner: -
--

ALTER TABLE ONLY cs.carga
    ADD CONSTRAINT carga_pkey PRIMARY KEY (id);


--
-- Name: evento evento_pkey; Type: CONSTRAINT; Schema: cs; Owner: -
--

ALTER TABLE ONLY cs.evento
    ADD CONSTRAINT evento_pkey PRIMARY KEY (id);


--
-- Name: contenedor_pendiente contenedor_pendiente_pkey; Type: CONSTRAINT; Schema: dt; Owner: -
--

ALTER TABLE ONLY dt.contenedor_pendiente
    ADD CONSTRAINT contenedor_pendiente_pkey PRIMARY KEY (tipo_servicio, bk, contenedor);


--
-- Name: contenedor contenedor_pkey; Type: CONSTRAINT; Schema: dt; Owner: -
--

ALTER TABLE ONLY dt.contenedor
    ADD CONSTRAINT contenedor_pkey PRIMARY KEY (tipo_servicio, bk, contenedor);


--
-- Name: isotype_catalogo isotype_catalogo_pkey; Type: CONSTRAINT; Schema: dt; Owner: -
--

ALTER TABLE ONLY dt.isotype_catalogo
    ADD CONSTRAINT isotype_catalogo_pkey PRIMARY KEY (isotype);


--
-- Name: liquidacion liquidacion_bl_contenedor_version_key; Type: CONSTRAINT; Schema: liq; Owner: -
--

ALTER TABLE ONLY liq.liquidacion
    ADD CONSTRAINT liquidacion_bl_contenedor_version_key UNIQUE (bl, contenedor, version);


--
-- Name: liquidacion_linea liquidacion_linea_pkey; Type: CONSTRAINT; Schema: liq; Owner: -
--

ALTER TABLE ONLY liq.liquidacion_linea
    ADD CONSTRAINT liquidacion_linea_pkey PRIMARY KEY (liquidacion_id, item);


--
-- Name: liquidacion liquidacion_pkey; Type: CONSTRAINT; Schema: liq; Owner: -
--

ALTER TABLE ONLY liq.liquidacion
    ADD CONSTRAINT liquidacion_pkey PRIMARY KEY (id);


--
-- Name: importacion_fila importacion_fila_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.importacion_fila
    ADD CONSTRAINT importacion_fila_pkey PRIMARY KEY (importacion_id, fila);


--
-- Name: importacion importacion_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.importacion
    ADD CONSTRAINT importacion_pkey PRIMARY KEY (id);


--
-- Name: movilizacion movilizacion_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.movilizacion
    ADD CONSTRAINT movilizacion_pkey PRIMARY KEY (id);


--
-- Name: programacion programacion_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.programacion
    ADD CONSTRAINT programacion_pkey PRIMARY KEY (id);


--
-- Name: servicio_adicional servicio_adicional_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.servicio_adicional
    ADD CONSTRAINT servicio_adicional_pkey PRIMARY KEY (id);


--
-- Name: cs_periodo cs_periodo_pkey; Type: CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.cs_periodo
    ADD CONSTRAINT cs_periodo_pkey PRIMARY KEY (tarifario_id, periodo);


--
-- Name: imo_clase imo_clase_pkey; Type: CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.imo_clase
    ADD CONSTRAINT imo_clase_pkey PRIMARY KEY (clase);


--
-- Name: recupero_concepto recupero_concepto_pkey; Type: CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.recupero_concepto
    ADD CONSTRAINT recupero_concepto_pkey PRIMARY KEY (concepto);


--
-- Name: regla regla_pkey; Type: CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.regla
    ADD CONSTRAINT regla_pkey PRIMARY KEY (id);


--
-- Name: tarifa tarifa_pkey; Type: CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.tarifa
    ADD CONSTRAINT tarifa_pkey PRIMARY KEY (id);


--
-- Name: tarifario tarifario_codigo_key; Type: CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.tarifario
    ADD CONSTRAINT tarifario_codigo_key UNIQUE (codigo);


--
-- Name: tarifario tarifario_pkey; Type: CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.tarifario
    ADD CONSTRAINT tarifario_pkey PRIMARY KEY (id);


--
-- Name: carga_en_stock_uk; Type: INDEX; Schema: cs; Owner: -
--

CREATE UNIQUE INDEX carga_en_stock_uk ON cs.carga USING btree (cliente_id, bl) WHERE (fecha_salida IS NULL);


--
-- Name: liquidacion_activa_uk; Type: INDEX; Schema: liq; Owner: -
--

CREATE UNIQUE INDEX liquidacion_activa_uk ON liq.liquidacion USING btree (bl, contenedor) WHERE (estado = ANY (ARRAY['EMITIDA'::text, 'FACTURADA'::text]));


--
-- Name: liquidacion_estado_idx; Type: INDEX; Schema: liq; Owner: -
--

CREATE INDEX liquidacion_estado_idx ON liq.liquidacion USING btree (estado, emitido_en DESC);


--
-- Name: movilizacion_cnt_idx; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX movilizacion_cnt_idx ON ops.movilizacion USING btree (contenedor, fecha);


--
-- Name: programacion_cnt_idx; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX programacion_cnt_idx ON ops.programacion USING btree (contenedor);


--
-- Name: programacion_fecha_idx; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX programacion_fecha_idx ON ops.programacion USING btree (fecha_retiro);


--
-- Name: servicio_adicional_cnt_idx; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX servicio_adicional_cnt_idx ON ops.servicio_adicional USING btree (contenedor);


--
-- Name: regla_tarifario_idx; Type: INDEX; Schema: tarifas; Owner: -
--

CREATE INDEX regla_tarifario_idx ON tarifas.regla USING btree (tarifario_id) WHERE activo;


--
-- Name: carga carga_cliente_id_fkey; Type: FK CONSTRAINT; Schema: cs; Owner: -
--

ALTER TABLE ONLY cs.carga
    ADD CONSTRAINT carga_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES core.cliente(id);


--
-- Name: evento evento_carga_id_fkey; Type: FK CONSTRAINT; Schema: cs; Owner: -
--

ALTER TABLE ONLY cs.evento
    ADD CONSTRAINT evento_carga_id_fkey FOREIGN KEY (carga_id) REFERENCES cs.carga(id);


--
-- Name: contenedor contenedor_clase_imo_fkey; Type: FK CONSTRAINT; Schema: dt; Owner: -
--

ALTER TABLE ONLY dt.contenedor
    ADD CONSTRAINT contenedor_clase_imo_fkey FOREIGN KEY (clase_imo) REFERENCES tarifas.imo_clase(clase);


--
-- Name: contenedor contenedor_isotype_fkey; Type: FK CONSTRAINT; Schema: dt; Owner: -
--

ALTER TABLE ONLY dt.contenedor
    ADD CONSTRAINT contenedor_isotype_fkey FOREIGN KEY (isotype) REFERENCES dt.isotype_catalogo(isotype);


--
-- Name: liquidacion liquidacion_cliente_id_fkey; Type: FK CONSTRAINT; Schema: liq; Owner: -
--

ALTER TABLE ONLY liq.liquidacion
    ADD CONSTRAINT liquidacion_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES core.cliente(id);


--
-- Name: liquidacion_linea liquidacion_linea_liquidacion_id_fkey; Type: FK CONSTRAINT; Schema: liq; Owner: -
--

ALTER TABLE ONLY liq.liquidacion_linea
    ADD CONSTRAINT liquidacion_linea_liquidacion_id_fkey FOREIGN KEY (liquidacion_id) REFERENCES liq.liquidacion(id);


--
-- Name: liquidacion liquidacion_tarifario_id_fkey; Type: FK CONSTRAINT; Schema: liq; Owner: -
--

ALTER TABLE ONLY liq.liquidacion
    ADD CONSTRAINT liquidacion_tarifario_id_fkey FOREIGN KEY (tarifario_id) REFERENCES tarifas.tarifario(id);


--
-- Name: importacion_fila importacion_fila_importacion_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.importacion_fila
    ADD CONSTRAINT importacion_fila_importacion_id_fkey FOREIGN KEY (importacion_id) REFERENCES ops.importacion(id) ON DELETE CASCADE;


--
-- Name: movilizacion movilizacion_importacion_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.movilizacion
    ADD CONSTRAINT movilizacion_importacion_id_fkey FOREIGN KEY (importacion_id) REFERENCES ops.importacion(id);


--
-- Name: programacion programacion_cliente_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.programacion
    ADD CONSTRAINT programacion_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES core.cliente(id);


--
-- Name: programacion programacion_importacion_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.programacion
    ADD CONSTRAINT programacion_importacion_id_fkey FOREIGN KEY (importacion_id) REFERENCES ops.importacion(id);


--
-- Name: servicio_adicional servicio_adicional_importacion_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.servicio_adicional
    ADD CONSTRAINT servicio_adicional_importacion_id_fkey FOREIGN KEY (importacion_id) REFERENCES ops.importacion(id);


--
-- Name: cs_periodo cs_periodo_tarifario_id_fkey; Type: FK CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.cs_periodo
    ADD CONSTRAINT cs_periodo_tarifario_id_fkey FOREIGN KEY (tarifario_id) REFERENCES tarifas.tarifario(id);


--
-- Name: regla regla_tarifario_id_fkey; Type: FK CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.regla
    ADD CONSTRAINT regla_tarifario_id_fkey FOREIGN KEY (tarifario_id) REFERENCES tarifas.tarifario(id);


--
-- Name: tarifario tarifario_cliente_id_fkey; Type: FK CONSTRAINT; Schema: tarifas; Owner: -
--

ALTER TABLE ONLY tarifas.tarifario
    ADD CONSTRAINT tarifario_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES core.cliente(id);


--
-- PostgreSQL database dump complete
--


