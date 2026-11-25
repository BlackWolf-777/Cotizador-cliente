export const usd = (n) => (n == null || n === '' ? '—' :
  Number(n).toLocaleString('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 }));
export const num = (n) => Number(n).toLocaleString('es-PE', { maximumFractionDigits: 2 });
export const fecha = (d) => {
  if (!d) return '—';
  const s = typeof d === 'string' ? d : d.toISOString();
  const [y, m, dd] = s.slice(0, 10).split('-');
  return `${dd}/${m}/${y}`;
};
export const fechaHora = (d) => d ? new Date(d).toLocaleString('es-PE', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Lima' }) : '—';
export const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
