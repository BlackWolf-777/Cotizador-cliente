'use client';
import { useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { usd, fecha } from '@/lib/format';
import LineasEditor, { AJUSTES_VACIOS, calcular, limpiar } from '@/components/LineasEditor';

const hoy = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/Lima' });

export default function Deposito() {
  const sp = useSearchParams();
  const [cargas, setCargas] = useState([]);
  const [bl, setBl] = useState(sp.get('bl') || '');
  const [fechaSal, setFechaSal] = useState('');
  const [d, setD] = useState(null);
  const [aj, setAj] = useState(AJUSTES_VACIOS);
  const [registrar, setRegistrar] = useState(true);
  const [usuario, setUsuario] = useState('');
  const [st, setSt] = useState(null);

  useEffect(() => { try { setUsuario(localStorage.getItem('usuario') || ''); } catch {} }, []);
  useEffect(() => {
    fetch('/api/cs/carga?estado=todas').then((r) => r.json()).then((x) => {
      const ds = (x.rows || []).filter((r) => r.modalidad === 'DEPOSITO_SIMPLE')
        .sort((a, b) => (a.fecha_salida ? 1 : 0) - (b.fecha_salida ? 1 : 0) || String(b.fecha_ingreso).localeCompare(String(a.fecha_ingreso)));
      setCargas(ds);
      if (!bl && ds.length) setBl(ds[0].bl);
    });
    // eslint-disable-next-line
  }, []);
  useEffect(() => {
    const c = cargas.find((x) => x.bl === bl);
    if (c) setFechaSal((c.fecha_salida || hoy()).slice(0, 10));
  }, [bl, cargas]);
  useEffect(() => {
    if (!bl || !fechaSal) return;
    setD(null); setSt(null); setAj(AJUSTES_VACIOS);
    fetch('/api/cs/deposito', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ bl, fecha: fechaSal }) })
      .then((r) => r.json()).then(setD);
  }, [bl, fechaSal]);

  async function emitir() {
    setSt({ cargando: true });
    const r = await fetch('/api/cs/deposito', { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ bl, fecha: fechaSal, accion: 'emitir', ajustes: limpiar(aj), registrar_salida: registrar, usuario: usuario || null }) })
      .then((x) => x.json());
    setSt(r.error ? { ok: false, msg: r.error } : { ok: true, id: r.liquidacion_id, version: r.version });
  }

  const j = d?.json, s = j?.servicio;
  const t = d && !d.error ? calcular(d.lineas, aj).t : null;
  const facturada = d?.activa?.estado === 'FACTURADA';
  const enStock = cargas.find((x) => x.bl === bl && !x.fecha_salida);

  return (
    <>
      <div className="card row" style={{ justifyContent: 'space-between' }}>
        <div className="row">
          <label className="f">BL / carta porte<select value={bl} onChange={(e) => setBl(e.target.value)}>
            {!cargas.length && <option value="">No hay carga terrestre registrada</option>}
            {cargas.map((c) => <option key={c.id} value={c.bl}>{c.bl} · ingreso {fecha(c.fecha_ingreso)}{c.fecha_salida ? ' · salió ' + fecha(c.fecha_salida) : ' · en stock'}</option>)}
          </select></label>
          <label className="f">Fecha de salida<input type="date" value={fechaSal} onChange={(e) => setFechaSal(e.target.value)} /></label>
        </div>
        <div className="row">
          <label className="f">Tu nombre (queda en la liquidación)<input value={usuario}
            onChange={(e) => { setUsuario(e.target.value); try { localStorage.setItem('usuario', e.target.value); } catch {} }} placeholder="Ej. Ana Torres" /></label>
          <Link className="btn" href="/carga-suelta">+ Registrar ingreso</Link>
        </div>
      </div>

      {!bl ? null : !d ? <div className="card">Calculando…</div> : d.error ? <div className="alert alto">{d.error}</div> :
        <div className="card bl">
          <div className="blhead">
            <div><h2 style={{ margin: 0 }} className="mono">{s.bl}</h2>
              <span className="muted">{j.cliente.razon_social} · tarifario {j.tarifario.codigo}</span></div>
            <div className="tot">{usd(t.total)}</div>
          </div>
          <div className="meta">
            <span>Ingreso <b>{fecha(s.fecha_ingreso)}</b></span><span>Salida <b>{fecha(s.fecha_retiro)}</b></span>
            <span>Días <b>{s.dias_en_deposito ?? '—'}</b> de {s.dias_libres} libres</span>
            {s.orden_servicio && <span>O/S <b>{s.orden_servicio}</b></span>}
            {s.bultos != null && <span>Carga <b>{Number(s.bultos)} {s.unidad_bulto || ''}</b></span>}
            {s.m2 != null && <span>Área <b>{Number(s.m2)} m²</b></span>}
            <span>Al recibir: montacarga <b>{Number(s.horas_montacarga_ingreso)} h</b>, cuadrilla <b>{Number(s.horas_cuadrilla_ingreso)} h</b></span>
          </div>
          {j.alertas.map((a, i) => <div key={i} className={`alert ${a.nivel}`}>{a.mensaje}</div>)}
          {d.activa && <div className={`alert ${facturada ? 'alto' : 'medio'}`}>
            {facturada ? `Ya facturado (factura ${d.activa.factura_numero}). Para volver a liquidar, anula primero la liquidación.`
              : `Ya existe la liquidación LQ-${String(d.activa.id).padStart(6, '0')} v${d.activa.version} (${usd(d.activa.total)}). Si emites, la reemplaza.`}
            {' '}<Link href={`/liquidacion/${d.activa.id}`}>Ver</Link></div>}
          <LineasEditor lineas={d.lineas} ajustes={aj} setAjustes={setAj} />
          <div className="row" style={{ justifyContent: 'flex-end', marginTop: 10, alignItems: 'center' }}>
            {enStock && <label style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              <input type="checkbox" checked={registrar} onChange={(e) => setRegistrar(e.target.checked)} /> Registrar la salida del stock (retiro, {fecha(fechaSal)})</label>}
            {st?.ok && <span className="alert ok" style={{ margin: 0 }}>Emitida <Link href={`/liquidacion/${st.id}`}>LQ-{String(st.id).padStart(6, '0')}</Link> (v{st.version})</span>}
            {st?.ok === false && <span className="alert alto" style={{ margin: 0 }}>{st.msg}</span>}
            <button className="btn p" onClick={emitir} disabled={facturada || st?.cargando || st?.ok || !t.total}>
              {st?.cargando ? 'Emitiendo…' : st?.ok ? 'Emitida' : 'Emitir a facturación'}</button>
          </div>
        </div>}
    </>
  );
}
