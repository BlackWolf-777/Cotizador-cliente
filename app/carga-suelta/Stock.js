'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { fecha, fechaHora, usd } from '@/lib/format';

const MOTIVOS = { RETIRO: 'Retiro', DESTRUCCION_SUNAT: 'Destrucción SUNAT', ADJUDICACION_SUNAT: 'Adjudicación SUNAT', OTRO: 'Otro' };
const MOD = { ALMACEN: 'Almacén', DEPOSITO_SIMPLE: 'Depósito simple' };
const hoy = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/Lima' });
const kg = (n) => (n == null ? '—' : Number(n).toLocaleString('es-PE', { maximumFractionDigits: 2 }) + ' kg');
const VACIO = { bl: '', modalidad: 'ALMACEN', cobra_almacenaje: true, nave: '', orden_servicio: '', bultos: '', unidad_bulto: 'CRTS',
  peso_kg: '', m2: '', ubicacion: 'ALMACEN', fecha_ingreso: hoy(), horas_montacarga: '', horas_cuadrilla: '', observacion: '' };

export default function Stock() {
  const [vista, setVista] = useState('stock');
  const [rows, setRows] = useState(null);
  const [msg, setMsg] = useState(null);
  const [usuario, setUsuario] = useState('');
  const [form, setForm] = useState(null);
  const [salida, setSalida] = useState(null);
  const [bitacora, setBitacora] = useState(null);
  const [filtro, setFiltro] = useState('');

  useEffect(() => { try { setUsuario(localStorage.getItem('usuario') || ''); } catch {} }, []);
  const cargar = (v = vista) => { setRows(null); fetch(`/api/cs/carga?estado=${v}`).then((r) => r.json()).then((d) => setRows(d.rows || [])); };
  useEffect(() => { cargar(vista); /* eslint-disable-next-line */ }, [vista]);

  async function post(body, okMsg) {
    setMsg(null);
    const r = await fetch('/api/cs/carga', { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ...body, usuario: usuario || null }) }).then((x) => x.json());
    if (r.error) { setMsg({ nivel: 'alto', mensaje: r.error }); return false; }
    setMsg({ nivel: 'ok', mensaje: okMsg }); cargar(); return true;
  }
  async function guardarIngreso() {
    const d = { ...form };
    if (d.modalidad === 'DEPOSITO_SIMPLE' && d.horas_cuadrilla === '') d.horas_cuadrilla = d.horas_montacarga;
    if (await post({ accion: 'ingreso', datos: d }, `BL ${form.bl.toUpperCase()} registrado en stock.`)) setForm(null);
  }
  async function guardarSalida() {
    if (await post({ accion: 'salida', ...salida }, 'Salida registrada. El BL queda en el historial de salidas.')) setSalida(null);
  }
  async function verBitacora(id) {
    if (bitacora?.carga?.id === id) return setBitacora(null);
    setBitacora(await fetch(`/api/cs/carga?id=${id}`).then((r) => r.json()));
  }
  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value }));

  const lista = (rows || []).filter((r) => !filtro || (r.bl + ' ' + (r.nave || '') + ' ' + (r.orden_servicio || '')).toUpperCase().includes(filtro.toUpperCase()));
  const pesoTotal = lista.reduce((s, r) => s + Number(r.peso_kg || 0), 0);

  return (
    <>
      <div className="card row" style={{ justifyContent: 'space-between' }}>
        <div className="row">
          <button className={`btn ${vista === 'stock' ? 'p' : ''}`} onClick={() => setVista('stock')}>En stock</button>
          <button className={`btn ${vista === 'salidas' ? 'p' : ''}`} onClick={() => setVista('salidas')}>Salidas</button>
          <input value={filtro} onChange={(e) => setFiltro(e.target.value)} placeholder="Buscar BL, nave u O/S" />
        </div>
        <div className="row">
          <label className="f">Tu nombre<input value={usuario} onChange={(e) => { setUsuario(e.target.value); try { localStorage.setItem('usuario', e.target.value); } catch {} }} placeholder="Ej. Ana Torres" /></label>
          <button className="btn p" onClick={() => setForm(form ? null : { ...VACIO })}>{form ? 'Cerrar' : '+ Registrar ingreso'}</button>
        </div>
      </div>
      {msg && <div className={`alert ${msg.nivel}`}>{msg.mensaje}</div>}

      {form && <div className="card bl">
        <h2>Registrar ingreso de carga suelta</h2>
        <div className="row" style={{ marginBottom: 10 }}>
          <label className="f">Tipo<select value={form.modalidad} onChange={(e) => {
            const m = e.target.value;
            setForm((f) => ({ ...f, modalidad: m, cobra_almacenaje: m === 'ALMACEN', unidad_bulto: m === 'ALMACEN' ? 'CRTS' : 'PALETAS', nave: m === 'ALMACEN' ? f.nave : (f.nave || 'VIA TERRESTRE') }));
          }}>
            <option value="ALMACEN">Almacén (stock, se cobra almacenaje mensual)</option>
            <option value="DEPOSITO_SIMPLE">Depósito simple (carga terrestre, 30 días libres)</option></select></label>
          <label className="f" style={{ alignSelf: 'center', display: 'flex', flexDirection: 'row', gap: 6, alignItems: 'center' }}>
            <input type="checkbox" checked={form.cobra_almacenaje} onChange={set('cobra_almacenaje')} /> Cobrar almacenaje mensual</label>
        </div>
        <div className="row" style={{ marginBottom: 10 }}>
          <label className="f">BL / carta porte *<input value={form.bl} onChange={set('bl')} placeholder="BLX0001234.1 o CRT-ANDES-07" /></label>
          <label className="f">Fecha de ingreso<input type="date" value={form.fecha_ingreso} onChange={set('fecha_ingreso')} /></label>
          <label className="f">Nave<input value={form.nave} onChange={set('nave')} /></label>
          <label className="f">O/S<input value={form.orden_servicio} onChange={set('orden_servicio')} style={{ width: 110 }} /></label>
        </div>
        <div className="row" style={{ marginBottom: 10 }}>
          <label className="f">Cantidad<input type="number" min="0" value={form.bultos} onChange={set('bultos')} style={{ width: 90 }} /></label>
          <label className="f">Unidad<select value={form.unidad_bulto} onChange={set('unidad_bulto')}><option>CRTS</option><option>PALETAS</option><option>BULTOS</option><option>CAJAS</option></select></label>
          <label className="f">Peso (kg){form.modalidad === 'ALMACEN' ? ' *' : ''}<input type="number" min="0" step="0.01" value={form.peso_kg} onChange={set('peso_kg')} style={{ width: 110 }} /></label>
          <label className="f">Área (m²)<input type="number" min="0" step="0.01" value={form.m2} onChange={set('m2')} style={{ width: 90 }} /></label>
          <label className="f">Ubicación<input value={form.ubicacion} onChange={set('ubicacion')} /></label>
        </div>
        {form.modalidad === 'DEPOSITO_SIMPLE' && <div className="row" style={{ marginBottom: 10 }}>
          <label className="f">Horas de montacarga al recibir<input type="number" min="0" step="0.5" value={form.horas_montacarga} onChange={set('horas_montacarga')} style={{ width: 110 }} /></label>
          <label className="f">Horas de cuadrilla al recibir<input type="number" min="0" step="0.5" value={form.horas_cuadrilla} onChange={set('horas_cuadrilla')} placeholder="= montacarga" style={{ width: 110 }} /></label>
          <span className="muted" style={{ fontSize: 12, alignSelf: 'center' }}>Lo que indica operaciones en el correo de ingreso. Al liquidar se propone el doble (recepción + despacho).</span>
        </div>}
        <label className="f" style={{ marginBottom: 10 }}>Observación<input value={form.observacion} onChange={set('observacion')} /></label>
        <button className="btn p" onClick={guardarIngreso} disabled={!form.bl.trim()}>Guardar ingreso</button>
      </div>}

      <div className="card tw">
        {rows === null ? <div className="empty">Cargando…</div> : lista.length === 0 ? <div className="empty">Sin carga {vista === 'stock' ? 'en stock' : 'con salida registrada'}.</div> : <>
          <p className="muted" style={{ marginTop: 0 }}><b>{lista.length}</b> BL · {kg(pesoTotal)}</p>
          <table><thead><tr><th>BL</th><th>Tipo</th><th>Nave</th><th>O/S</th><th className="n">Cant.</th><th className="n">Peso</th><th>Ubicación</th><th>Ingreso</th>
            {vista === 'salidas' ? <><th>Salida</th><th>Motivo</th></> : <th className="n">Días</th>}<th>Almacenaje</th><th></th></tr></thead>
            <tbody>{lista.map((r) => (<FilaCarga key={r.id} r={r} vista={vista} salida={salida} setSalida={setSalida} guardarSalida={guardarSalida}
              post={post} bitacora={bitacora?.carga?.id === r.id ? bitacora : null} verBitacora={verBitacora} />))}</tbody></table></>}
      </div>
    </>
  );
}

function FilaCarga({ r, vista, salida, setSalida, guardarSalida, post, bitacora, verBitacora }) {
  const abierta = salida?.id === r.id;
  const cols = vista === 'salidas' ? 12 : 11;
  return (
    <>
      <tr>
        <td><b className="mono">{r.bl}</b>{r.observacion && <div className="muted" style={{ fontSize: 11, maxWidth: 260 }}>{r.observacion}</div>}</td>
        <td><span className="pill tag">{MOD[r.modalidad]}</span></td>
        <td>{r.nave || '—'}</td><td className="mono">{r.orden_servicio || '—'}</td>
        <td className="n">{r.bultos != null ? Number(r.bultos) + ' ' + (r.unidad_bulto || '') : '—'}</td>
        <td className="n">{kg(r.peso_kg)}{Number(r.peso_kg) >= 1000 && <div><span className="pill EMITIDA">≥ 1 TN</span></div>}</td>
        <td>{r.ubicacion || '—'}</td>
        <td>{r.fecha_ingreso ? fecha(r.fecha_ingreso) : <span className="muted">sin fecha</span>}</td>
        {vista === 'salidas'
          ? <><td>{fecha(r.fecha_salida)}</td><td>{MOTIVOS[r.motivo_salida]}{r.detalle_salida && <div className="muted" style={{ fontSize: 11 }}>{r.detalle_salida}</div>}</td></>
          : <td className="n">{r.dias ?? '—'}</td>}
        <td>{r.fecha_salida ? (r.cobra_almacenaje ? 'Sí' : 'No') :
          <label style={{ display: 'flex', gap: 4, alignItems: 'center' }} title="Incluir en la liquidación mensual de almacenaje">
            <input type="checkbox" checked={r.cobra_almacenaje}
              onChange={(e) => post({ accion: 'actualizar', id: r.id, datos: { cobra_almacenaje: e.target.checked } },
                `${r.bl}: ${e.target.checked ? 'se cobrará' : 'no se cobrará'} almacenaje mensual.`)} /> {r.cobra_almacenaje ? 'Sí' : 'No'}</label>}</td>
        <td style={{ whiteSpace: 'nowrap' }}>
          {r.modalidad === 'DEPOSITO_SIMPLE' && (r.liquidacion
            ? <Link className="btn sm" href={`/liquidacion/${r.liquidacion.id}`}>LQ-{String(r.liquidacion.id).padStart(6, '0')}</Link>
            : <Link className="btn sm p" href={`/carga-suelta/deposito?bl=${encodeURIComponent(r.bl)}`}>Liquidar</Link>)}{' '}
          {!r.fecha_salida && <button className="btn sm" onClick={() => setSalida(abierta ? null : { id: r.id, fecha: hoy(), motivo: 'RETIRO', detalle: '' })}>Salida</button>}{' '}
          {r.fecha_salida && <button className="btn sm" onClick={() => {
            const m = prompt(`¿Por qué se revierte la salida de ${r.bl}? (vuelve al stock y queda registrado)`);
            if (m) post({ accion: 'revertir', id: r.id, motivo: m }, `${r.bl} volvió al stock.`);
          }}>Revertir</button>}{' '}
          <button className="btn sm" onClick={() => verBitacora(r.id)}>Historial</button>
        </td>
      </tr>
      {abierta && <tr><td colSpan={cols} style={{ background: 'var(--soft)' }}>
        <div className="row">
          <b style={{ alignSelf: 'center' }}>Salida de {r.bl}</b>
          <label className="f">Fecha<input type="date" value={salida.fecha} onChange={(e) => setSalida((s) => ({ ...s, fecha: e.target.value }))} /></label>
          <label className="f">Motivo<select value={salida.motivo} onChange={(e) => setSalida((s) => ({ ...s, motivo: e.target.value }))}>
            {Object.entries(MOTIVOS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
          <label className="f" style={{ flex: 1, minWidth: 220 }}>Detalle / sustento{salida.motivo === 'OTRO' ? ' *' : ''}
            <input value={salida.detalle} onChange={(e) => setSalida((s) => ({ ...s, detalle: e.target.value }))} placeholder="Ej. Acta SUNAT N°…, correo de operaciones del…" /></label>
          <button className="btn p" onClick={guardarSalida}>Registrar salida</button>
        </div>
        <p className="muted" style={{ fontSize: 12, marginBottom: 0 }}>El BL no se borra: pasa a "Salidas" con su fecha y motivo. En la liquidación de ese mes se cobran los días hasta la salida.</p>
      </td></tr>}
      {bitacora && <tr><td colSpan={cols} style={{ background: 'var(--soft)' }}>
        <b>Historial de {r.bl}</b>
        <table style={{ marginTop: 6 }}><tbody>{bitacora.eventos.map((e, i) => (<tr key={i}>
          <td className="muted" style={{ width: 150 }}>{fechaHora(e.en)}</td><td><span className="pill tag">{e.tipo.replace('_', ' ')}</span></td>
          <td style={{ fontSize: 12 }}>{resumen(e)}</td><td className="muted">{e.usuario || '—'}</td></tr>))}</tbody></table>
        {r.liquidacion && <p style={{ fontSize: 12 }}>Liquidación activa: <Link href={`/liquidacion/${r.liquidacion.id}`}>LQ-{String(r.liquidacion.id).padStart(6, '0')}</Link> ({r.liquidacion.estado}, {usd(r.liquidacion.total)})</p>}
      </td></tr>}
    </>
  );
}

function resumen(e) {
  const d = e.detalle || {};
  if (e.tipo === 'SALIDA') return `${MOTIVOS[d.motivo] || d.motivo} el ${fecha(d.fecha)}${d.detalle ? ' · ' + d.detalle : ''}`;
  if (e.tipo === 'SALIDA_REVERTIDA') return `Se anuló la salida del ${fecha(d.fecha)} (${MOTIVOS[d.motivo] || d.motivo}): ${d.razon}`;
  if (e.tipo === 'CAMBIO') return Object.entries(d).map(([k, v]) => `${k.replace('_', ' ')}: ${v.antes ?? '—'} → ${v.despues ?? '—'}`).join(' · ');
  if (d.origen) return d.origen;
  return 'Ingreso registrado' + (d.fecha_ingreso ? ' el ' + fecha(d.fecha_ingreso) : '');
}
