import { q } from '@/lib/db';
import { ok, fail } from '@/lib/api';

export const dynamic = 'force-dynamic';

// GET ?estado=stock|salidas|todas  ·  ?id=N devuelve además la bitácora
export async function GET(req) {
  try {
    const sp = new URL(req.url).searchParams;
    const id = sp.get('id');
    if (id) {
      const [carga] = await q('SELECT * FROM cs.v_carga WHERE id = $1', [id]);
      const eventos = await q('SELECT tipo, detalle, usuario, en FROM cs.evento WHERE carga_id = $1 ORDER BY en, id', [id]);
      return ok({ carga, eventos });
    }
    const estado = sp.get('estado') || 'stock';
    const where = estado === 'stock' ? 'fecha_salida IS NULL' : estado === 'salidas' ? 'fecha_salida IS NOT NULL' : 'true';
    const rows = await q(`SELECT * FROM cs.v_carga WHERE ${where}
      ORDER BY ${estado === 'salidas' ? 'fecha_salida DESC, bl' : 'modalidad DESC, fecha_ingreso DESC NULLS LAST, bl'}`);
    return ok({ rows });
  } catch (e) { return fail(e); }
}

// POST {accion: ingreso|salida|revertir|actualizar, ...}
export async function POST(req) {
  try {
    const b = await req.json();
    const u = b.usuario || null;
    if (b.accion === 'ingreso') {
      const [r] = await q('SELECT cs.registrar_ingreso($1::jsonb, $2) AS id', [JSON.stringify(b.datos || {}), u]);
      return ok(r);
    }
    if (b.accion === 'salida') {
      await q('SELECT cs.registrar_salida($1, $2::date, $3, $4, $5)', [b.id, b.fecha || null, b.motivo, b.detalle || null, u]);
      return ok({ ok: true });
    }
    if (b.accion === 'revertir') {
      await q('SELECT cs.revertir_salida($1, $2, $3)', [b.id, b.motivo || null, u]);
      return ok({ ok: true });
    }
    if (b.accion === 'actualizar') {
      await q('SELECT cs.actualizar($1, $2::jsonb, $3)', [b.id, JSON.stringify(b.datos || {}), u]);
      return ok({ ok: true });
    }
    return fail('Acción no válida');
  } catch (e) { return fail(e); }
}
