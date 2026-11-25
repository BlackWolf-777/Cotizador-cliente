'use client';
import { use, useEffect, useState } from 'react';
import Link from 'next/link';
import { usd, fecha, fechaHora } from '@/lib/format';

export default function Liquidacion({ params }) {
  const { id } = use(params);
  const [d, setD] = useState(null);
  const [factura, setFactura] = useState('');
  const [motivo, setMotivo] = useState('');
  const [msg, setMsg] = useState(null);
  const [verJson, setVerJson] = useState(false);
  const cargar = () => fetch(`/api/liquidacion/${id}`).then((r) => r.json()).then(setD);
  useEffect(() => { cargar(); /* eslint-disable-next-line */ }, [id]);

  if (!d) return <div className="card">Cargando…</div>;
  if (d.error) return <div className="alert alto">{d.error}</div>;
  const l = d.liquidacion, j = l.json, s = j.servicio, codigo = `LQ-${String(l.id).padStart(6, '0')}`;
  const usuario = (() => { try { return localStorage.getItem('usuario') || null; } catch { return null; } })();

  async function accion(body) {
    setMsg(null);
    const r = await fetch(`/api/liquidacion/${id}`, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ...body, usuario }) }).then((x) => x.json());
    if (r.error) setMsg({ nivel: 'alto', mensaje: r.error }); else { setMsg({ nivel: 'ok', mensaje: 'Guardado.' }); cargar(); }
  }
  const bajar = () => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([JSON.stringify(j, null, 2)], { type: 'application/json' }));
    a.download = `${codigo}-${j.tipo?.startsWith('CS') ? s.bl.replace(/\s+/g, '_') : s.contenedor}.json`; a.click();
  };

  return (
    <>
      <div className="blhead">
        <div><h1 className="mono">{codigo} <span className="muted" style={{ fontSize: 15 }}>v{l.version}</span></h1>
          <p className="sub">Factura a <b>{j.cliente.razon_social}</b> · RUC {j.cliente.ruc ?? 'pendiente'} · tarifario {j.tarifario.codigo}
            {j.acuerdo?.tipo === 'AGENCIA' && <> · acuerdo con la agencia <b>{j.acuerdo.nombre}</b></>}</p></div>
        <span className={`pill ${l.estado}`} style={{ fontSize: 13 }}>{l.estado}</span>
      </div>
      {msg && <div className={`alert ${msg.nivel}`}>{msg.mensaje}</div>}
      <div className="card">
        {j.tipo === 'CS_MENSUAL' ? <div className="meta" style={{ fontSize: 13 }}>
          <span>Tipo <b>Almacenaje mensual de carga suelta</b></span><span>Periodo <b>{fecha(s.desde)} al {fecha(s.hasta)}</b></span>
          <span>BLs <b>{s.bls}</b></span></div>
        : j.tipo === 'CS_DEPOSITO' ? <div className="meta" style={{ fontSize: 13 }}>
          <span>Tipo <b>Carga suelta en depósito simple</b></span><span>BL <b>{s.bl}</b></span>
          {s.orden_servicio && <span>O/S <b>{s.orden_servicio}</b></span>}
          <span>Ingreso <b>{fecha(s.fecha_ingreso)}</b></span><span>Salida <b>{fecha(s.fecha_retiro)}</b></span><span>Días <b>{s.dias_en_deposito}</b></span>
          {s.bultos != null && <span>Carga <b>{Number(s.bultos)} {s.unidad_bulto || ''}</b></span>}</div>
        : <div className="meta" style={{ fontSize: 13 }}>
          <span>BL <b>{s.bl}</b></span><span>Contenedor <b className="mono">{s.contenedor}</b></span>
          <span>Tipo <b>{s.tamano}' {s.clase} · {s.tipo_carga}{s.clase_imo ? ' ' + s.clase_imo : ''}</b></span>
          <span>Puerto <b>{s.operador_portuario}</b></span><span>Ingreso <b>{fecha(s.fecha_ingreso)}</b></span>
          <span>Retiro <b>{fecha(s.fecha_retiro)}</b></span><span>Días <b>{s.dias_en_deposito}</b></span>
          {s.linea_naviera && <span>Línea <b>{s.linea_naviera}</b></span>}
          {s.agencia_aduana && <span>Agencia <b>{s.agencia_aduana}</b></span>}
        </div>}
        <div className="tw"><table>
          <thead><tr><th>#</th><th>Rubro</th><th>Concepto</th><th>Unidad</th><th className="n">Tarifa</th><th className="n">Cant.</th><th className="n">Neto</th><th className="n">IGV</th><th className="n">Total</th></tr></thead>
          <tbody>{j.lineas.map((x) => (<tr key={x.item}><td>{x.item}</td><td className="mono">{x.rubro ?? '—'}</td><td>{x.concepto}</td>
            <td className="muted">{x.unidad_negocio}</td><td className="n">{usd(x.tarifa)}</td><td className="n">{x.cantidad}</td>
            <td className="n">{usd(x.neto)}</td><td className="n">{usd(x.igv)}</td><td className="n">{usd(x.total)}</td></tr>))}</tbody>
          <tfoot><tr><td colSpan={6}>Total USD</td><td className="n">{usd(j.totales.neto)}</td><td className="n">{usd(j.totales.igv)}</td><td className="n">{usd(j.totales.total)}</td></tr></tfoot>
        </table></div>
        <p className="muted" style={{ fontSize: 12, marginBottom: 0 }}>
          Emitida {fechaHora(l.emitido_en)}{l.emitido_por ? ' por ' + l.emitido_por : ''} · huella <span className="mono">{l.hash.slice(0, 16)}…</span>
          {l.factura_numero && <> · factura <b>{l.factura_numero}</b> ({fechaHora(l.facturado_en)}{l.facturado_por ? ', ' + l.facturado_por : ''})</>}
          {l.anulado_motivo && <> · anulada: {l.anulado_motivo}</>}</p>
      </div>
      {j.tipo === 'CS_MENSUAL' && j.detalle?.length > 0 && <div className="card tw">
        <h2>Detalle por BL</h2>
        <table><thead><tr><th>BL</th><th>Nave</th><th className="n">Peso</th><th>Ingreso</th><th>Salida</th><th className="n">Días</th>
          <th className="n">P1</th><th className="n">P2</th><th className="n">P3</th><th className="n">P4</th><th className="n">Importe</th></tr></thead>
          <tbody>{j.detalle.map((x) => (<tr key={x.bl}><td className="mono">{x.bl}</td><td>{x.nave || '—'}</td>
            <td className="n">{Number(x.peso_kg).toLocaleString('es-PE')} kg</td><td>{fecha(x.fecha_ingreso)}</td><td>{fecha(x.fecha_salida)}</td>
            <td className="n">{x.dias}</td>
            {[1, 2, 3, 4].map((p) => { const pe = x.periodos.find((y) => y.periodo === p); return <td key={p} className="n">{pe ? `${pe.dias} × ${Number(pe.tarifa).toFixed(2)}${x.tarifa_por_tonelada ? ' × ' + pe.factor_tn + ' TN' : ''}` : '—'}</td>; })}
            <td className="n">{usd(x.importe)}</td></tr>))}</tbody></table>
      </div>}

      <div className="two">
        <div className="card">
          <h2>Facturación</h2>
          <div className="row" style={{ marginBottom: 10 }}>
            <button className="btn" onClick={() => navigator.clipboard.writeText(JSON.stringify(j, null, 2)).then(() => setMsg({ nivel: 'ok', mensaje: 'JSON copiado.' }))}>Copiar JSON</button>
            <button className="btn" onClick={bajar}>Descargar JSON</button>
            <button className="btn" onClick={() => setVerJson((v) => !v)}>{verJson ? 'Ocultar' : 'Ver'} JSON</button>
          </div>
          {l.estado === 'EMITIDA' && <div className="row">
            <label className="f">N° de factura<input value={factura} onChange={(e) => setFactura(e.target.value)} placeholder="F001-000123" /></label>
            <button className="btn p" onClick={() => accion({ accion: 'facturar', factura })} disabled={!factura.trim()}>Marcar como facturada</button></div>}
          {(l.estado === 'EMITIDA' || l.estado === 'FACTURADA') && <div className="row" style={{ marginTop: 12 }}>
            <label className="f" style={{ flex: 1 }}>Motivo de anulación<input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Ej. cambio de fecha de retiro, nota de crédito…" /></label>
            <button className="btn d" onClick={() => accion({ accion: 'anular', motivo })} disabled={!motivo.trim()}>Anular</button></div>}
        </div>
        <div className="card">
          <h2>Versiones</h2>
          <table><tbody>{d.versiones.map((v) => (<tr key={v.id}><td className="mono"><Link href={`/liquidacion/${v.id}`}>v{v.version}</Link></td>
            <td><span className={`pill ${v.estado}`}>{v.estado}</span></td><td className="n">{usd(v.total)}</td><td className="muted">{fechaHora(v.emitido_en)}</td></tr>))}</tbody></table>
          {j.alertas?.length > 0 && <><h2 style={{ marginTop: 14 }}>Alertas al emitir</h2>{j.alertas.map((a, i) => <div key={i} className={`alert ${a.nivel}`}>{a.mensaje}</div>)}</>}
        </div>
      </div>
      {verJson && <pre className="json">{JSON.stringify(j, null, 2)}</pre>}
    </>
  );
}
