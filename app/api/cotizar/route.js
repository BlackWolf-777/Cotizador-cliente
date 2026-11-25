import { q } from '@/lib/db';
import { ok, fail } from '@/lib/api';

const ES_CONTENEDOR = /^[A-Z]{4}\d{7}$/;

// Recibe contenedores y/o BL. Un BL se expande a todos sus contenedores según la data del DT.
// Si algo no está en la data del DT, no se cotiza: se devuelve "no hay información".
export async function POST(req) {
  try {
    const { entradas = [], fecha } = await req.json();
    if (!fecha) return fail('Indique la fecha de retiro');
    const lista = [...new Set(entradas.map((c) => String(c).toUpperCase().trim()).filter(Boolean))].slice(0, 60);

    const objetivos = []; // { contenedor, bl, entrada }
    const out = [];
    for (const e of lista) {
      if (ES_CONTENEDOR.test(e)) { objetivos.push({ contenedor: e, bl: null, entrada: e }); continue; }
      const cnts = await q('SELECT contenedor FROM liq.contenedores_de_bl($1)', [e]);
      if (!cnts.length) out.push({ contenedor: e, entrada: e, ok: false, error: `No hay información del BL ${e} en la data del DT` });
      else cnts.forEach((c) => objetivos.push({ contenedor: c.contenedor, bl: e, entrada: e }));
    }

    const vistos = new Set();
    for (const o of objetivos) {
      if (vistos.has(o.contenedor)) continue;
      vistos.add(o.contenedor);
      try {
        const lineas = await q('SELECT * FROM liq.cotizar($1, $2::date, $3)', [o.contenedor, fecha, o.bl]);
        const [{ j }] = await q('SELECT liq.cotizar_json($1, $2::date, $3) AS j', [o.contenedor, fecha, o.bl]);
        const activa = await q(
          `SELECT id, version, estado, total, factura_numero FROM liq.liquidacion
           WHERE contenedor = $1 AND bl = $2 AND estado IN ('EMITIDA','FACTURADA')`, [o.contenedor, j.servicio.bl]);
        out.push({ contenedor: o.contenedor, entrada: o.entrada, ok: true, lineas, json: j, activa: activa[0] || null });
      } catch (e) {
        const valido = await q('SELECT core.iso6346_valido($1) v', [o.contenedor]);
        out.push({ contenedor: o.contenedor, entrada: o.entrada, ok: false, error: e.message, isoValido: valido[0].v });
      }
    }
    return ok({ resultados: out });
  } catch (e) { return fail(e, 500); }
}
