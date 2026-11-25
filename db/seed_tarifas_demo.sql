-- =====================================================================
-- Tarifarios de DEMOSTRACIÓN (empresas, RUC y montos ficticios).
-- =====================================================================
BEGIN;
-- Tablas de referencia
INSERT INTO core.parametro VALUES ('IGV', 0.18, 'Tasa de IGV aplicada a cada línea');
INSERT INTO dt.isotype_catalogo VALUES ('20ST', 20, 'ST');
INSERT INTO dt.isotype_catalogo VALUES ('40ST', 40, 'ST');
INSERT INTO dt.isotype_catalogo VALUES ('40HC', 40, 'HC');
INSERT INTO dt.isotype_catalogo VALUES ('20RH', 20, 'RH');
INSERT INTO dt.isotype_catalogo VALUES ('40RH', 40, 'RH');
INSERT INTO dt.isotype_catalogo VALUES ('20OT', 20, 'OT');
INSERT INTO dt.isotype_catalogo VALUES ('40OT', 40, 'OT');
INSERT INTO tarifas.imo_clase VALUES ('Clase 1', 'A');
INSERT INTO tarifas.imo_clase VALUES ('Clase 5.2', 'A');
INSERT INTO tarifas.imo_clase VALUES ('Clase 6.2', 'A');
INSERT INTO tarifas.imo_clase VALUES ('Clase 7', 'A');
INSERT INTO tarifas.imo_clase VALUES ('Clase 9', 'B');
INSERT INTO tarifas.imo_clase VALUES ('Clase 2', 'C');
INSERT INTO tarifas.imo_clase VALUES ('Clase 3', 'C');
INSERT INTO tarifas.imo_clase VALUES ('Clase 4', 'C');
INSERT INTO tarifas.imo_clase VALUES ('Clase 5.1', 'C');
INSERT INTO tarifas.imo_clase VALUES ('Clase 6.1', 'C');
INSERT INTO tarifas.imo_clase VALUES ('Clase 8', 'C');
INSERT INTO tarifas.recupero_concepto VALUES ('USO DE AREA OPERATIVA', 'REFACTURAR', 'Uso de área operativa en puerto (20/40): se traslada al cliente');
INSERT INTO tarifas.recupero_concepto VALUES ('LAR', 'REFACTURAR', 'LAR: se traslada al cliente');
INSERT INTO tarifas.recupero_concepto VALUES ('CARGA IMO', 'CUBIERTO_TARIFA', 'La segregación IMO ya se cobra por tarifario');
INSERT INTO tarifas.recupero_concepto VALUES ('RECARGO POR CARGA PELIGROSA', 'CUBIERTO_TARIFA', 'La segregación IMO ya se cobra por tarifario');
INSERT INTO tarifas.recupero_concepto VALUES ('CONTENEDOR DE ALTO CUBICAJE', 'CUBIERTO_TARIFA', 'Alto cubicaje ya se cobra por tarifario');
INSERT INTO tarifas.recupero_concepto VALUES ('MOVILIZACION PARA INSPECCION NO INTRUSIVA', 'DISPARA_SINI', 'Se cobra la tarifa SINI del tarifario');
INSERT INTO tarifas.recupero_concepto VALUES ('MONITOREO DE REEFERS', 'CUBIERTO_TARIFA', 'Monitoreo RH ya se cobra por día');
INSERT INTO tarifas.recupero_concepto VALUES ('MONITOREO REEFER', 'CUBIERTO_TARIFA', 'Monitoreo RH ya se cobra por día');
INSERT INTO tarifas.recupero_concepto VALUES ('ENERGIA', 'CUBIERTO_TARIFA', 'Energía RH ya se cobra por día');

-- Partes con acuerdo comercial: un cliente (factura a sí mismo) y una agencia de aduana (factura a cada consignatario)
INSERT INTO core.cliente (ruc, razon_social, nombre_corto, alias, tipo) VALUES
  (20100000017, 'IMPORTADORA ANDINA S.A.C.', 'Importadora Andina', ARRAY['IMPORTADORA ANDINA S.A.C.','IMPORTADORA ANDINA SAC','IMPORTADORA ANDINA'], 'CLIENTE'),
  (20100000025, 'ADUANAS MI PERU S.A.C.', 'Aduanas Mi Perú', ARRAY['ADUANAS MI PERU'], 'AGENCIA');

INSERT INTO tarifas.tarifario (cliente_id, codigo, nombre, operacion, vigente_desde, dias_libres, umbral_kg, documento, notas)
SELECT id, 'DEMO-ANDINA-FCL', 'Importación FCL (acuerdo con el cliente)', 'IMPO_FCL', DATE '2026-01-01', 30, NULL, 'Tarifario demo', 'Tarifas ficticias' FROM core.cliente WHERE nombre_corto = 'Importadora Andina'
UNION ALL
SELECT id, 'DEMO-ANDINA-CS', 'Carga suelta (almacén y depósito simple)', 'CARGA_SUELTA', DATE '2026-01-01', 30, 1000, 'Tarifario demo', 'Periodos que se reinician cada mes' FROM core.cliente WHERE nombre_corto = 'Importadora Andina'
UNION ALL
SELECT id, 'DEMO-MIPERU-FCL', 'Importación DRY/RH (acuerdo con la agencia)', 'IMPO_FCL', DATE '2026-01-01', 30, NULL, 'Tarifario demo', 'Se factura a cada consignatario' FROM core.cliente WHERE nombre_corto = 'Aduanas Mi Perú';

DO $$
DECLARE a int; p int; c int;
BEGIN
  SELECT id INTO a FROM tarifas.tarifario WHERE codigo = 'DEMO-ANDINA-FCL';
  SELECT id INTO p FROM tarifas.tarifario WHERE codigo = 'DEMO-MIPERU-FCL';
  SELECT id INTO c FROM tarifas.tarifario WHERE codigo = 'DEMO-ANDINA-CS';

  -- Acuerdo con el cliente (FCL)
  INSERT INTO tarifas.regla (tarifario_id, codigo_rubro, concepto, unidad_negocio, puerto, tipo_carga, tamano, grupo_imo, monto, unidad, disparador, orden, removible, sugerir_si, pendiente) VALUES
  (a, 101, 'DERECHO A LA DESCARGA', 'DT', 'APM', 'DRY', '20', NULL, 420, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (a, 101, 'DERECHO A LA DESCARGA', 'DT', 'APM', 'DRY', '40', NULL, 560, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (a, 101, 'DERECHO A LA DESCARGA', 'DT', 'DPW', 'DRY', '20', NULL, 330, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (a, 101, 'DERECHO A LA DESCARGA', 'DT', 'DPW', 'DRY', '40', NULL, 450, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (a, 101, 'DERECHO A LA DESCARGA', 'DT', 'APM', 'RH',  '20', NULL, 450, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (a, 101, 'DERECHO A LA DESCARGA', 'DT', 'APM', 'RH',  '40', NULL, 620, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (a, 101, 'DERECHO A LA DESCARGA', 'DT', 'DPW', 'RH',  '20', NULL, 360, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (a, 101, 'DERECHO A LA DESCARGA', 'DT', 'DPW', 'RH',  '40', NULL, 480, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (a, 104, 'CONTENEDORES ALTO CUBICAJE', 'DT', 'APM', 'TODOS', '40', NULL, 25, 'CONTENEDOR', 'SIEMPRE', 20, false, NULL, NULL),
  (a, 104, 'CONTENEDORES ALTO CUBICAJE', 'DT', 'DPW', 'TODOS', '40', NULL, 30, 'CONTENEDOR', 'SIEMPRE', 20, false, NULL, NULL),
  (a, 105, 'VERIFICACION DE DATOS', 'DT', 'DPW', 'TODOS', 'TODOS', NULL, 35, 'CONTENEDOR', 'DPW', 25, false, NULL, NULL),
  (a, 106, 'TRACCION IMO', 'DT', 'TODOS', 'IMO', 'TODOS', NULL, 75, 'CONTENEDOR', 'IMO', 30, false, NULL, NULL),
  (a, 108, 'RECEPCION CONT. REEFER', 'DT', 'DPW', 'RH', 'TODOS', NULL, 170, 'CONTENEDOR', 'CONEXION', 40, false, NULL, NULL),
  (a, 109, 'MONITOREO DE CARGA RH', 'DT', 'TODOS', 'RH', 'TODOS', NULL, 15, 'DIA', 'CONEXION', 40, false, NULL, NULL),
  (a, 110, 'SUMINISTRO DE ENERGIA RH', 'DT', 'TODOS', 'RH', 'TODOS', NULL, 35, 'DIA', 'CONEXION', 40, false, NULL, NULL),
  (a, 111, 'EST/DESES CONT 20 - CUADRILLA', 'DT', 'TODOS', 'TODOS', '20', NULL, 30, 'EVENTO', 'CUADRILLA', 50, false, NULL, NULL),
  (a, 111, 'EST/DESES CONT 40 - CUADRILLA', 'DT', 'TODOS', 'TODOS', '40', NULL, 35, 'EVENTO', 'CUADRILLA', 50, false, NULL, NULL),
  (a, 112, 'MANIPULEO DE CARGA - POSICIONAMIENTO 20', 'DT', 'TODOS', 'TODOS', '20', NULL, 30, 'EVENTO', 'MANIPULEO', 52, false, NULL, NULL),
  (a, 112, 'MANIPULEO DE CARGA - POSICIONAMIENTO 40', 'DT', 'TODOS', 'TODOS', '40', NULL, 35, 'EVENTO', 'MANIPULEO', 52, false, NULL, NULL),
  (a, 113, 'EST/DES 20 - MONTACARGAS 3TM', 'DT', 'TODOS', 'TODOS', '20', NULL, 30, 'EVENTO', 'MONTACARGA', 55, false, NULL, NULL),
  (a, 113, 'EST/DES 40 - MONTACARGAS 3TM', 'DT', 'TODOS', 'TODOS', '40', NULL, 35, 'EVENTO', 'MONTACARGA', 55, false, NULL, NULL),
  (a, 114, 'SINI - INSPECCION NO INTRUSIVA', 'DT', 'TODOS', 'TODOS', 'TODOS', NULL, 160, 'EVENTO', 'SINI', 60, false, NULL, NULL),
  (a, 115, 'ALMACENAJE DESDE EL DIA 31 - CNT 20', 'DT', 'TODOS', 'TODOS', '20', NULL, 30, 'DIA', 'ALMACENAJE', 70, true, NULL, NULL),
  (a, 115, 'ALMACENAJE DESDE EL DIA 31 - CNT 40', 'DT', 'TODOS', 'TODOS', '40', NULL, 50, 'DIA', 'ALMACENAJE', 70, true, NULL, NULL),
  (a, 116, 'GASTOS ADMIN. RECUPERO SOBRECOSTOS', 'DT', 'TODOS', 'TODOS', 'TODOS', NULL, 25, 'EVENTO', 'RECUPERO_ADMIN', 85, false, NULL, NULL),
  (a, 120, 'TRANSPORTE ZONA 1', 'INLAND', 'TODOS', 'DRY', 'TODOS', NULL, 165, 'CONTENEDOR', 'SIEMPRE', 90, true, NULL, NULL),
  (a, 120, 'TRANSPORTE RH', 'INLAND', 'TODOS', 'RH', 'TODOS', NULL, 250, 'CONTENEDOR', 'SIEMPRE', 90, true, NULL, NULL),
  (a, 140, 'PERNOCTE', 'INLAND', 'TODOS', 'TODOS', 'TODOS', NULL, 80, 'NOCHE', 'MANUAL', 95, false, NULL, NULL),
  (a, 103, 'RECARGO A LA DESCARGA (CONGESTION PORTUARIA)', 'INLAND', 'TODOS', 'TODOS', 'TODOS', NULL, 50, 'EVENTO', 'MANUAL', 96, false, NULL, NULL),
  (a, 141, 'RECARGO DEVOLUCION/RETIRO EN APM o DPW', 'INLAND', 'TODOS', 'TODOS', 'TODOS', NULL, 40, 'EVENTO', 'MANUAL', 97, false, 'DEPOT_PUERTO', NULL),
  (a, 142, 'STAND BY DEVOLUCION/RETIRO (por hora)', 'INLAND', 'TODOS', 'TODOS', 'TODOS', NULL, 40, 'HORA', 'MANUAL', 98, false, NULL, 'Después de 2 horas de espera');
  INSERT INTO tarifas.regla (tarifario_id, codigo_rubro, concepto, puerto, tipo_carga, tamano, grupo_imo, monto, unidad, disparador, orden)
  SELECT t, 107, 'SEGREGACION CARGA PELIGROSA', v.pto, 'IMO', v.tam, v.g, v.m, 'CONTENEDOR', 'IMO', 30
  FROM unnest(ARRAY[a, p]) t, (VALUES ('APM','20','A',270),('APM','20','B',130),('APM','20','C',160),('APM','40','A',540),('APM','40','B',260),('APM','40','C',320),
                                      ('DPW','20','A',290),('DPW','20','B',190),('DPW','20','C',190),('DPW','40','A',580),('DPW','40','B',380),('DPW','40','C',380)) v(pto, tam, g, m);

  -- Acuerdo con la agencia de aduana (se factura a cada consignatario)
  INSERT INTO tarifas.regla (tarifario_id, codigo_rubro, concepto, unidad_negocio, puerto, tipo_carga, tamano, monto, unidad, disparador, orden, removible, sugerir_si, pendiente) VALUES
  (p, 101, 'DERECHO A LA DESCARGA', 'DT', 'APM', 'DRY', '20', 380, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (p, 101, 'DERECHO A LA DESCARGA', 'DT', 'APM', 'DRY', '40', 550, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (p, 101, 'DERECHO A LA DESCARGA', 'DT', 'DPW', 'DRY', '20', 300, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (p, 101, 'DERECHO A LA DESCARGA', 'DT', 'DPW', 'DRY', '40', 400, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (p, 101, 'DERECHO A LA DESCARGA', 'DT', 'APM', 'RH',  '20', 430, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (p, 101, 'DERECHO A LA DESCARGA', 'DT', 'APM', 'RH',  '40', 620, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (p, 101, 'DERECHO A LA DESCARGA', 'DT', 'DPW', 'RH',  '20', 320, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (p, 101, 'DERECHO A LA DESCARGA', 'DT', 'DPW', 'RH',  '40', 430, 'CONTENEDOR', 'SIEMPRE', 10, false, NULL, NULL),
  (p, 102, 'SERVICIO DE TERMINAL', 'DT', 'TODOS', 'TODOS', 'TODOS', 250, 'CONTENEDOR', 'SIEMPRE', 12, false, NULL, NULL),
  (p, 103, 'RECARGO A LA DESCARGA (20% SERV. TERMINAL)', 'DT', 'TODOS', 'TODOS', 'TODOS', 50, 'CONTENEDOR', 'SIEMPRE', 13, false, NULL, NULL),
  (p, 130, 'RECARGO DT (COMBUSTIBLE)', 'DT', 'TODOS', 'TODOS', 'TODOS', 20, 'CONTENEDOR', 'SIEMPRE', 14, false, NULL, NULL),
  (p, 104, 'CONTENEDORES ALTO CUBICAJE', 'DT', 'APM', 'TODOS', '40', 25, 'CONTENEDOR', 'SIEMPRE', 20, false, NULL, NULL),
  (p, 104, 'CONTENEDORES ALTO CUBICAJE', 'DT', 'DPW', 'TODOS', '40', 30, 'CONTENEDOR', 'SIEMPRE', 20, false, NULL, NULL),
  (p, 105, 'VERIFICACION DE DATOS', 'DT', 'DPW', 'TODOS', 'TODOS', 36, 'CONTENEDOR', 'DPW', 25, false, NULL, NULL),
  (p, 108, 'RECEPCION CONT. REEFER', 'DT', 'DPW', 'RH', 'TODOS', 165, 'CONTENEDOR', 'CONEXION', 40, false, NULL, NULL),
  (p, 109, 'CONTROL Y MONITOREO RH', 'DT', 'TODOS', 'RH', 'TODOS', 15, 'DIA', 'CONEXION', 40, false, NULL, NULL),
  (p, 110, 'SUMINISTRO DE ENERGIA RH', 'DT', 'TODOS', 'RH', 'TODOS', 35, 'DIA', 'CONEXION', 40, false, NULL, NULL),
  (p, 111, 'EST/DESES CONT 20 - CUADRILLA', 'DT', 'TODOS', 'TODOS', '20', 35, 'EVENTO', 'CUADRILLA', 50, false, NULL, NULL),
  (p, 111, 'EST/DESES CONT 40 - CUADRILLA', 'DT', 'TODOS', 'TODOS', '40', 35, 'EVENTO', 'CUADRILLA', 50, false, NULL, NULL),
  (p, 112, 'MANIPULEO DE CARGA - USO DE GRUA', 'DT', 'TODOS', 'TODOS', 'TODOS', 35, 'EVENTO', 'MANIPULEO', 52, false, NULL, NULL),
  (p, 113, 'EST/DES 20 - MONTACARGAS 3TM', 'DT', 'TODOS', 'TODOS', '20', 35, 'EVENTO', 'MONTACARGA', 55, false, NULL, NULL),
  (p, 113, 'EST/DES 40 - MONTACARGAS 3TM', 'DT', 'TODOS', 'TODOS', '40', 35, 'EVENTO', 'MONTACARGA', 55, false, NULL, NULL),
  (p, 114, 'SINI - INSPECCION NO INTRUSIVA', 'DT', 'TODOS', 'TODOS', 'TODOS', 180, 'EVENTO', 'SINI', 60, false, NULL, NULL),
  (p, 115, 'ALMACENAJE DESDE EL DIA 31 - CNT 20', 'DT', 'TODOS', 'TODOS', '20', 30, 'DIA', 'ALMACENAJE', 70, true, NULL, NULL),
  (p, 115, 'ALMACENAJE DESDE EL DIA 31 - CNT 40', 'DT', 'TODOS', 'TODOS', '40', 52, 'DIA', 'ALMACENAJE', 70, true, NULL, NULL),
  (p, 116, 'GASTOS ADMIN. RECUPERO SOBRECOSTOS', 'DT', 'TODOS', 'TODOS', 'TODOS', 25, 'EVENTO', 'RECUPERO_ADMIN', 85, false, NULL, NULL),
  (p, 120, 'TRANSPORTE DRY - CALLAO', 'INLAND', 'TODOS', 'TODOS', 'TODOS', 160, 'CONTENEDOR', 'MANUAL', 90, false, NULL, NULL),
  (p, 120, 'TRANSPORTE DRY - LIMA CENTRO', 'INLAND', 'TODOS', 'TODOS', 'TODOS', 200, 'CONTENEDOR', 'MANUAL', 90, false, NULL, NULL),
  (p, 120, 'TRANSPORTE DRY - LIMA ESTE', 'INLAND', 'TODOS', 'TODOS', 'TODOS', 230, 'CONTENEDOR', 'MANUAL', 90, false, NULL, NULL),
  (p, 120, 'TRANSPORTE DRY - LIMA SUR', 'INLAND', 'TODOS', 'TODOS', 'TODOS', 265, 'CONTENEDOR', 'MANUAL', 90, false, NULL, NULL),
  (p, 120, 'TRANSPORTE DRY - LURIN', 'INLAND', 'TODOS', 'TODOS', 'TODOS', 335, 'CONTENEDOR', 'MANUAL', 90, false, NULL, NULL),
  (p, 150, 'TRASEGADO DRY', 'DT', 'TODOS', 'TODOS', 'TODOS', 190, 'EVENTO', 'MANUAL', 92, false, NULL, 'Incluye posicionamiento, 1 h de montacarga o cuadrilla y devolución del vacío'),
  (p, 151, 'DESPACHO DE CARGA SUELTA DRY', 'DT', 'TODOS', 'TODOS', 'TODOS', 120, 'EVENTO', 'MANUAL', 92, false, NULL, NULL),
  (p, 140, 'PERNOCTE', 'INLAND', 'TODOS', 'TODOS', 'TODOS', 40, 'NOCHE', 'MANUAL', 95, false, NULL, NULL),
  (p, 141, 'RECARGO DEVOLUCION/RETIRO EN APM o DPW', 'INLAND', 'TODOS', 'TODOS', 'TODOS', 40, 'EVENTO', 'MANUAL', 97, false, 'DEPOT_PUERTO', NULL),
  (p, 142, 'STAND BY DEVOLUCION/RETIRO (por hora)', 'INLAND', 'TODOS', 'TODOS', 'TODOS', 40, 'HORA', 'MANUAL', 98, false, NULL, 'Después de 2 horas de espera');

  -- Carga suelta del cliente
  INSERT INTO tarifas.cs_periodo (tarifario_id, periodo, dia_desde, dia_hasta, codigo_rubro, tarifa_menor, tarifa_mayor) VALUES
  (c, 1, 1, 5, 160, 0.80, 1.10), (c, 2, 6, 10, 160, 0.80, 1.10), (c, 3, 11, 20, 160, 1.30, 1.60), (c, 4, 21, NULL, 160, 1.80, 2.10);
  INSERT INTO tarifas.regla (tarifario_id, codigo_rubro, concepto, unidad_negocio, monto, unidad, disparador, orden, removible) VALUES
  (c, 102, 'SERVICIO DE TERMINAL (INGRESO)', 'DT', 380, 'EVENTO', 'CS_INGRESO', 10, false),
  (c, 120, 'TRANSPORTE', 'INLAND', 150, 'VUELTA', 'CS_TRANSPORTE', 20, true),
  (c, 113, 'MANIPULEO MONTACARGA DEP SIMPLE (HORAS)', 'DT', 30, 'HORA', 'CS_MONTACARGA', 30, true),
  (c, 111, 'CUADRILLA (HORAS)', 'DT', 35, 'HORA', 'CS_CUADRILLA', 40, true),
  (c, 116, 'GASTOS ADMIN X BL', 'DT', 0, 'BL', 'MANUAL', 90, false);
END $$;

COMMIT;
