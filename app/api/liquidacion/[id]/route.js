import { q } from '@/lib/db';
import { ok, fail } from '@/lib/api';

export async function GET(_req, { params }) {
  const { id } = await params;
  const r = await q('SELECT * FROM liq.liquidacion WHERE id = $1', [id]);
  if (!r[0]) return fail('No existe', 404);
  const versiones = await q(
    `SELECT id, version, estado, total, emitido_en, emitido_por, factura_numero, anulado_motivo
     FROM liq.liquidacion WHERE bl = $1 AND contenedor = $2 ORDER BY version DESC`, [r[0].bl, r[0].contenedor]);
  return ok({ liquidacion: r[0], versiones });
}

// Acciones: { accion: 'facturar', factura, usuario } | { accion: 'anular', motivo, usuario }
export async function POST(req, { params }) {
  const { id } = await params;
  try {
    const b = await req.json();
    if (b.accion === 'facturar') await q('SELECT liq.marcar_facturada($1, $2, $3)', [id, b.factura, b.usuario || null]);
    else if (b.accion === 'anular') await q('SELECT liq.anular($1, $2, $3)', [id, b.motivo, b.usuario || null]);
    else return fail('Acción no reconocida');
    return ok({ ok: true });
  } catch (e) { return fail(e); }
}
