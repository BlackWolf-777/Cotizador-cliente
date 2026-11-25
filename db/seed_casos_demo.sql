-- Casos para mostrar la demo completa: un contenedor sin acuerdo comercial y algunas liquidaciones ya emitidas.
BEGIN;
INSERT INTO dt.contenedor (tipo_servicio, bk, contenedor, clase_cnt, tamano_cnt, isotype, condicion_cnt, tipo_carga, fecha_ingreso_balanza,
                           hora_ingreso_balanza, cliente, ruc_cliente, operador_portuario, conexion, linea_maritima, agencia_aduana, mercaderia)
VALUES ('IMPO', 'XYZ2611004', 'LOGU1001010', 'ST', 20, '20ST', 'FCL', 'DRY', current_date - 4, '09:30', 'COMERCIAL XYZ S.A.C.', 20300000013,
        'APM', false, 'MAERSK', 'ADUANAS DEL SUR S.A.C.', 'Ejemplo: cliente y agencia sin acuerdo comercial');

-- Liquidaciones emitidas (historial y bandeja de facturación)
DO $$
DECLARE r record; n int := 0; v_id bigint;
BEGIN
  FOR r IN SELECT c.contenedor, c.bk, c.fecha_ingreso_balanza FROM dt.contenedor c
           WHERE c.fecha_ingreso_balanza < current_date - 12 AND c.agencia_aduana <> 'ADUANAS DEL SUR S.A.C.'
           ORDER BY c.fecha_ingreso_balanza DESC LIMIT 6
  LOOP
    n := n + 1;
    SELECT liquidacion_id INTO v_id FROM liq.emitir(r.contenedor, r.fecha_ingreso_balanza + 9, r.bk, '{}'::jsonb, 'Ana Torres', 'REAL');
    IF n <= 3 THEN PERFORM liq.marcar_facturada(v_id, 'F001-' || lpad((1200 + n)::text, 6, '0'), 'Facturación'); END IF;
    IF n = 6 THEN PERFORM liq.anular(v_id, 'Ejemplo: cambio de fecha de retiro', 'Ana Torres'); END IF;
  END LOOP;
  -- Carga suelta: almacenaje del mes anterior (facturado) y la carga terrestre
  SELECT liquidacion_id INTO v_id FROM cs.emitir_mensual(20100000017, (date_trunc('month', current_date) - interval '1 month')::date, '{}'::jsonb, 'Ana Torres');
  PERFORM liq.marcar_facturada(v_id, 'F001-001250', 'Facturación');
  PERFORM cs.emitir_deposito(k.bl, k.fecha_salida, '{}'::jsonb, 'Ana Torres', 'REAL', false)
  FROM cs.carga k WHERE k.modalidad = 'DEPOSITO_SIMPLE' AND k.fecha_salida IS NOT NULL LIMIT 1;
END $$;
COMMIT;
