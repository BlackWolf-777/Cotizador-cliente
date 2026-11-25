'use client';
export default function DescargarLote({ ids }) {
  async function bajar() {
    const items = await Promise.all(ids.map((id) => fetch(`/api/liquidacion/${id}`).then((r) => r.json())));
    const lote = { tipo: 'LOTE_LIQUIDACIONES', generado_en: new Date().toISOString(), cantidad: items.length,
      liquidaciones: items.map((i) => i.liquidacion.json) };
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([JSON.stringify(lote, null, 2)], { type: 'application/json' }));
    a.download = `lote-por-facturar-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
  }
  return <button className="btn" onClick={bajar} disabled={!ids.length}>Descargar lote JSON</button>;
}
