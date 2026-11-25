import { pool, q } from '@/lib/db';
import { ok, fail } from '@/lib/api';

export const maxDuration = 60;

const PROCESOS = {
  MOVILIZACIONES: 'SELECT * FROM ops.procesar_movilizaciones($1)',
  SERV_ADICIONALES: 'SELECT * FROM ops.procesar_servicios_adicionales($1)',
  DT: 'SELECT * FROM ops.procesar_dt($1)',
};

// Flujo en 3 pasos para soportar archivos grandes:
//  { paso:'iniciar', tipo, archivo, filas, usuario } -> { id }
//  { paso:'filas', id, filas:[{fila, datos}] }        (en bloques)
//  { paso:'procesar', id, clienteId? }                -> resumen
export async function POST(req) {
  try {
    const b = await req.json();
    if (b.paso === 'iniciar') {
      if (!PROCESOS[b.tipo]) return fail('Tipo de archivo no reconocido');
      const r = await q('INSERT INTO ops.importacion (tipo, archivo, filas, creado_por) VALUES ($1,$2,$3,$4) RETURNING id',
        [b.tipo, b.archivo, b.filas || 0, b.usuario || null]);
      return ok({ id: r[0].id });
    }
    if (b.paso === 'filas') {
      const filas = b.filas || [];
      if (!filas.length) return ok({ insertadas: 0 });
      await q(
        `INSERT INTO ops.importacion_fila (importacion_id, fila, datos)
         SELECT $1, (x->>'fila')::int, x->'datos' FROM jsonb_array_elements($2::jsonb) x
         ON CONFLICT DO NOTHING`, [b.id, JSON.stringify(filas)]);
      return ok({ insertadas: filas.length });
    }
    if (b.paso === 'procesar') {
      const [imp] = await q('SELECT tipo FROM ops.importacion WHERE id = $1', [b.id]);
      if (!imp) return fail('Importación no encontrada');
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const r = await client.query(PROCESOS[imp.tipo], [b.id]);
        await client.query('COMMIT');
        const [res] = await q('SELECT id, tipo, filas, aceptadas, rechazadas, detalle FROM ops.importacion WHERE id = $1', [b.id]);
        return ok({ ...res, resultado: r.rows[0] });
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      } finally { client.release(); }
    }
    return fail('Paso no reconocido');
  } catch (e) { return fail(e, 500); }
}
