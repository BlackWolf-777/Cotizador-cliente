'use client';
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usd, fecha } from '@/lib/format';
import LineasEditor, { AJUSTES_VACIOS, calcular, limpiar } from '@/components/LineasEditor';

const MOTIVOS = { RETIRO: 'retiro', DESTRUCCION_SUNAT: 'destrucción SUNAT', ADJUDICACION_SUNAT: 'adjudicación SUNAT', OTRO: 'otro' };
const mesActual = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/Lima' }).slice(0, 7);
const nombreMes = (m) => new Date(m + '-15').toLocaleDateString('es-PE', { month: 'long', year: 'numeric' });

export default function Mensual() {
  const [mes, setMes] = useState(mesActual());
  const [d, setD] = useState(null);
  const [aj, setAj] = useState(AJUSTES_VACIOS);
  const [usuario, setUsuario] = useState('');
  const [st, setSt] = useState(null);

  useEffect(() => { try { setUsuario(localStorage.getItem('usuario') || ''); } catch {} }, []);
  useEffect(() => {
    setD(null); setSt(null); setAj(AJUSTES_VACIOS);
    fetch('/api/cs/mensual', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ mes }) })
      .then((r) => r.json()).then(setD);
  }, [mes]);

  async function emitir() {
    setSt({ cargando: true });
    const r = await fetch('/api/cs/mensual', { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ mes, accion: 'emitir', ajustes: limpiar(aj), usuario: usuario || null }) }).then((x) => x.json());
    setSt(r.error ? { ok: false, msg: r.error } : { ok: true, id: r.liquidacion_id, version: r.version });
  }

  const j = d?.json;
  const excluidos = new Set(aj.excluir);
  const blQuitado = (bl) => d.lineas.some((l) => l.bl === bl && excluidos.has(l.item));
  const t = d && !d.error ? calcular(d.lineas, aj).t : null;
  const facturada = d?.activa?.estado === 'FACTURADA';

  return (
    <>
      <div className="card row" style={{ justifyContent: 'space-between' }}>
        <div className="row">
          <label className="f">Mes a liquidar<input type="month" value={mes} onChange={(e) => e.target.value && setMes(e.target.value)} /></label>
          <span className="muted" style={{ alignSelf: 'center' }}>Cliente: Importadora Andina S.A.C.</span>
        </div>
        <label className="f">Tu nombre (queda en la liquidación)<input value={usuario}
          onChange={(e) => { setUsuario(e.target.value); try { localStorage.setItem('usuario', e.target.value); } catch {} }} placeholder="Ej. Ana Torres" /></label>
      </div>

      {!d ? <div className="card">Calculando…</div> : d.error ? <div className="alert alto">{d.error}</div> : <>
        <div className="card bl">
          <div className="blhead">
            <div><h2 style={{ margin: 0 }}>Almacenaje de {nombreMes(mes)}</h2>
              <span className="muted">{j.detalle.length} BL · del {fecha(j.servicio.desde)} al {fecha(j.servicio.hasta)} · tarifario {j.tarifario.codigo}</span></div>
            <div className="tot">{usd(t.total)}</div>
          </div>
          {j.alertas.map((a, i) => <div key={i} className={`alert ${a.nivel}`}>{a.mensaje}</div>)}
          {d.activa && <div className={`alert ${facturada ? 'alto' : 'medio'}`}>
            {facturada ? `Este mes ya fue facturado (factura ${d.activa.factura_numero}). Para volver a liquidar, anula primero la liquidación.`
              : `Ya existe la liquidación LQ-${String(d.activa.id).padStart(6, '0')} v${d.activa.version} de este mes (${usd(d.activa.total)}). Si emites, la reemplaza.`}
            {' '}<Link href={`/liquidacion/${d.activa.id}`}>Ver</Link></div>}

          <div className="tw"><table>
            <thead><tr><th>BL</th><th>Nave</th><th className="n">Cant.</th><th className="n">Peso</th><th>Ingreso</th><th>Salida</th>
              <th className="n">Días</th><th className="n">P1</th><th className="n">P2</th><th className="n">P3</th><th className="n">P4</th><th className="n">Importe</th></tr></thead>
            <tbody>{j.detalle.length === 0 && <tr><td colSpan={12} className="empty">Sin BLs.</td></tr>}
              {[...j.detalle, ...d.lineas.filter((l) => l.bl && blQuitado(l.bl)).map((l) => ({ bl: l.bl, quitado: true }))]
                .sort((a, b) => a.bl.localeCompare(b.bl)).map((x) => x.quitado
                ? <tr key={x.bl} className="off"><td className="c mono">{x.bl}</td><td colSpan={11} className="muted">Quitado de esta liquidación</td></tr>
                : <tr key={x.bl}>
                  <td className="mono">{x.bl}</td><td>{x.nave || '—'}</td><td className="n">{x.bultos != null ? Number(x.bultos) : '—'}</td>
                  <td className="n">{Number(x.peso_kg).toLocaleString('es-PE')} kg{x.tarifa_por_tonelada && <div><span className="pill EMITIDA">por TN</span></div>}</td>
                  <td>{x.fecha_ingreso ? fecha(x.fecha_ingreso) : <span className="muted">antes</span>}</td>
                  <td>{x.fecha_salida ? <>{fecha(x.fecha_salida)}<div className="muted" style={{ fontSize: 11 }}>{MOTIVOS[x.motivo_salida]}</div></> : '—'}</td>
                  <td className="n"><b>{x.dias}</b></td>
                  {[1, 2, 3, 4].map((p) => { const pe = x.periodos.find((y) => y.periodo === p);
                    return <td key={p} className="n">{pe ? <>{pe.dias}<div className="muted" style={{ fontSize: 11 }}>× {Number(pe.tarifa).toFixed(2)}</div></> : '—'}</td>; })}
                  <td className="n">{usd(x.importe)}</td>
                </tr>)}</tbody>
          </table></div>
        </div>

        <div className="card">
          <h2>Liquidación</h2>
          <p className="muted" style={{ marginTop: 0, fontSize: 12 }}>Una línea por BL (rubro 801). Con ✕ quitas un BL; con "Agregar" sumas un recurso (gastos administrativos, cuadrilla, etc.) y puedes poner su tarifa.</p>
          <LineasEditor lineas={d.lineas} ajustes={aj} setAjustes={setAj} compacto />
          <div className="row" style={{ justifyContent: 'flex-end', marginTop: 10 }}>
            {st?.ok && <span className="alert ok" style={{ margin: 0 }}>Emitida <Link href={`/liquidacion/${st.id}`}>LQ-{String(st.id).padStart(6, '0')}</Link> (v{st.version})</span>}
            {st?.ok === false && <span className="alert alto" style={{ margin: 0 }}>{st.msg}</span>}
            <button className="btn p" onClick={emitir} disabled={facturada || st?.cargando || st?.ok || !t.total}>
              {st?.cargando ? 'Emitiendo…' : st?.ok ? 'Emitida' : 'Emitir a facturación'}</button>
          </div>
        </div>
      </>}
    </>
  );
}
