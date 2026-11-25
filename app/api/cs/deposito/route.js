import { q } from '@/lib/db';
import { ok, fail } from '@/lib/api';

// POST {bl, fecha, ajustes, accion: 'cotizar'|'emitir', registrar_salida, usuario}
export async function POST(req) {
  try {
    const { bl, fecha = null, ajustes = {}, accion = 'cotizar', registrar_salida = true, usuario = null } = await req.json();
    if (accion === 'emitir') {
      const [r] = await q('SELECT * FROM cs.emitir_deposito($1, $2::date, $3::jsonb, $4, $5, $6)',
        [bl, fecha, JSON.stringify(ajustes), usuario, 'REAL', registrar_salida]);
      return ok(r);
    }
    const [{ lineas, json }] = await q('SELECT cs.deposito_lineas($1, $2::date) AS lineas, cs.deposito_json($1, $2::date, $3::jsonb) AS json',
      [bl, fecha, JSON.stringify(ajustes)]);
    const [activa] = await q(`SELECT id, version, estado, factura_numero, total FROM liq.liquidacion
      WHERE bl = $1 AND contenedor = $2 AND estado IN ('EMITIDA','FACTURADA')`, [json.servicio.bl, json.servicio.contenedor]);
    return ok({ lineas, json, activa: activa || null });
  } catch (e) { return fail(e); }
}
