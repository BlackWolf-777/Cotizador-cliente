import { Pool } from 'pg';

const g = globalThis;
export const pool =
  g.__pool ||
  new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: /localhost|127\.0\.0\.1|\/var\/run/.test(process.env.DATABASE_URL || '') ? false : { rejectUnauthorized: false },
    max: 5,
  });
if (!g.__pool) g.__pool = pool;

export async function q(sql, params = []) {
  const r = await pool.query(sql, params);
  return r.rows;
}

export function errorMsg(e) {
  return (e && e.message ? e.message : String(e)).replace(/^error:\s*/i, '');
}
