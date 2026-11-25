import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { Client } from 'pg';

const ARCHIVOS = ['schema.sql', 'seed_tarifas_demo.sql', 'seed_datos_demo.sql', 'seed_casos_demo.sql'];

// Borra y vuelve a crear la base de la demo: esquema, tarifarios ficticios, datas anonimizadas y casos de ejemplo.
// Usa una conexión propia porque el esquema cambia el search_path de la sesión.
export async function reiniciarDemo() {
  const url = process.env.DATABASE_URL;
  const c = new Client({ connectionString: url, ssl: /localhost|127\.0\.0\.1/.test(url || '') ? false : { rejectUnauthorized: false } });
  await c.connect();
  const t0 = Date.now();
  try {
    await c.query('DROP SCHEMA IF EXISTS cs, liq, tarifas, ops, dt, core CASCADE');
    for (const f of ARCHIVOS) {
      const sql = await readFile(path.join(process.cwd(), 'db', f), 'utf8');
      await c.query(sql);
    }
    const { rows: [r] } = await c.query(`SELECT (SELECT count(*) FROM dt.contenedor)::int AS contenedores,
      (SELECT count(*) FROM liq.liquidacion)::int AS liquidaciones, (SELECT count(*) FROM cs.carga)::int AS carga_suelta`);
    return { ok: true, segundos: (Date.now() - t0) / 1000, ...r };
  } finally {
    await c.end();
  }
}
