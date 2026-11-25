import { q } from '@/lib/db';
import { ok, fail } from '@/lib/api';

const RUC = 20100000017; // cliente con acuerdo de carga suelta (demo)

// POST {mes:'2026-11', ajustes, accion: 'cotizar'|'emitir', usuario}
export async function POST(req) {
  try {
    const { mes, ajustes = {}, accion = 'cotizar', usuario = null, ruc = RUC } = await req.json();
    const fecha = `${mes}-01`;
    if (accion === 'emitir') {
      const [r] = await q('SELECT * FROM cs.emitir_mensual($1, $2::date, $3::jsonb, $4)', [ruc, fecha, JSON.stringify(ajustes), usuario]);
      return ok(r);
    }
    const [{ lineas, json }] = await q('SELECT cs.mensual_lineas($1, $2::date) AS lineas, cs.mensual_json($1, $2::date, $3::jsonb) AS json',
      [ruc, fecha, JSON.stringify(ajustes)]);
    const [activa] = await q(`SELECT id, version, estado, factura_numero, total FROM liq.liquidacion
      WHERE bl = $1 AND contenedor = $2 AND estado IN ('EMITIDA','FACTURADA')`, [json.servicio.bl, json.servicio.contenedor]);
    return ok({ lineas, json, activa: activa || null });
  } catch (e) { return fail(e); }
}
