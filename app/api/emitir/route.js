import { q } from '@/lib/db';
import { ok, fail } from '@/lib/api';

export async function POST(req) {
  try {
    const { contenedor, fecha, bl, ajustes = {}, usuario = null, origen = 'REAL' } = await req.json();
    const r = await q('SELECT * FROM liq.emitir($1, $2::date, $3, $4::jsonb, $5, $6)',
      [contenedor, fecha, bl || null, JSON.stringify(ajustes), usuario, origen]);
    return ok(r[0]);
  } catch (e) { return fail(e); }
}
