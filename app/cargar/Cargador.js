'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';

const TIPOS = {
  DT: { t: 'Data del DT', d: 'Características de cada contenedor: puerto, tamaño, tipo, IMO, ingreso (columnas de dt.contenedor)' },
  MOVILIZACIONES: { t: 'Control Movilizaciones', d: 'Costos adicionales del DT: aforo, SENASA, cuadrilla, montacargas' },
  SERV_ADICIONALES: { t: 'Servicios adicionales (puerto)', d: 'Facturación del puerto (APM/DPW): uso de área, SINI, citas…' },
};
const BLOQUE = 1500;

async function leerArchivo(file) {
  const nombre = file.name.toLowerCase();
  if (nombre.endsWith('.csv') || nombre.endsWith('.txt')) {
    const Papa = (await import('papaparse')).default;
    const buf = await file.arrayBuffer();
    let txt;
    try { txt = new TextDecoder('utf-8', { fatal: true }).decode(buf); } catch { txt = new TextDecoder('windows-1252').decode(buf); }
    const r = Papa.parse(txt, { header: true, skipEmptyLines: 'greedy', transformHeader: (h) => h.trim() });
    return r.data;
  }
  const XLSX = await import('xlsx');
  const wb = XLSX.read(await file.arrayBuffer(), { type: 'array', cellDates: true });
  const ws = wb.Sheets[wb.SheetNames[0]];
  return XLSX.utils.sheet_to_json(ws, { defval: '', raw: true });
}

function limpiar(rows) {
  const out = [];
  rows.forEach((r, i) => {
    const datos = {};
    for (const [k, v] of Object.entries(r)) {
      const key = String(k).trim();
      if (!key || key.startsWith('__EMPTY')) continue;
      let val = v instanceof Date ? v.toISOString().slice(0, 10) : String(v ?? '').trim();
      if (val) datos[key] = val;
    }
    if (Object.keys(datos).length) out.push({ fila: i + 2, datos });
  });
  return out;
}

export default function Cargador() {
  const router = useRouter();
  const [tipo, setTipo] = useState('MOVILIZACIONES');
  const [file, setFile] = useState(null);
  const [prog, setProg] = useState(0);
  const [estado, setEstado] = useState(null);
  const [res, setRes] = useState(null);

  const post = (b) => fetch('/api/importar', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(b) })
    .then(async (r) => { const j = await r.json(); if (j.error) throw new Error(j.error); return j; });

  async function subir() {
    setRes(null); setProg(0);
    try {
      setEstado('Leyendo archivo…');
      const filas = limpiar(await leerArchivo(file));
      if (!filas.length) throw new Error('El archivo no tiene filas con datos');
      let usuario = null; try { usuario = localStorage.getItem('usuario'); } catch {}
      const { id } = await post({ paso: 'iniciar', tipo, archivo: file.name, filas: filas.length, usuario });
      for (let i = 0; i < filas.length; i += BLOQUE) {
        setEstado(`Subiendo filas ${i + 1}–${Math.min(i + BLOQUE, filas.length)} de ${filas.length}…`);
        await post({ paso: 'filas', id, filas: filas.slice(i, i + BLOQUE) });
        setProg(Math.round(((i + BLOQUE) / filas.length) * 90));
      }
      setEstado('Validando y procesando…');
      const r = await post({ paso: 'procesar', id });
      setProg(100); setEstado(null); setRes(r); router.refresh();
    } catch (e) { setEstado(null); setRes({ error: e.message }); }
  }

  return (
    <div className="card">
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit,minmax(220px,1fr))', marginBottom: 12 }}>
        {Object.entries(TIPOS).map(([k, v]) => (
          <label key={k} className="card" style={{ margin: 0, cursor: 'pointer', borderColor: tipo === k ? 'var(--brand)' : undefined, background: tipo === k ? 'var(--brand-soft)' : undefined }}>
            <input type="radio" name="tipo" checked={tipo === k} onChange={() => setTipo(k)} style={{ marginRight: 6 }} />
            <b>{v.t}</b><div className="muted" style={{ fontSize: 12 }}>{v.d}</div></label>))}
      </div>
      <div className="row">
        <label className="f">Archivo (.xlsx o .csv)<input type="file" accept=".xlsx,.xls,.csv,.txt" onChange={(e) => setFile(e.target.files[0] || null)} /></label>
        <button className="btn p" onClick={subir} disabled={!file || !!estado}>Cargar</button>
      </div>
      {(estado || prog > 0) && <div style={{ marginTop: 12 }}><div className="prog"><div style={{ width: prog + '%' }} /></div>
        {estado && <p className="muted">{estado}</p>}</div>}
      {res?.error && <div className="alert alto">{res.error}</div>}
      {res && !res.error && <>
        <div className="alert ok">Carga #{res.id}: {res.aceptadas} filas válidas, {res.rechazadas} rechazadas, de {res.filas}.</div>
        {res.detalle?.length > 0 && <details><summary className="muted">Ver filas rechazadas ({res.detalle.length}{res.detalle.length >= 500 ? '+' : ''})</summary>
          <div className="tw" style={{ maxHeight: 300, overflow: 'auto' }}><table><thead><tr><th>Fila del Excel</th><th>Motivo</th></tr></thead>
            <tbody>{res.detalle.map((d, i) => <tr key={i}><td>{d.fila}</td><td>{d.motivo}</td></tr>)}</tbody></table></div></details>}
      </>}
    </div>
  );
}
