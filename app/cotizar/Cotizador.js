'use client';
import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { usd, fecha as fmtFecha, r2 } from '@/lib/format';

const IGV = 0.18;
const manana = () => { const d = new Date(); d.setDate(d.getDate() + 1); return d.toISOString().slice(0, 10); };
// Entradas: contenedores (4 letras + 7 dígitos, con o sin espacio) y BL (cualquier código alfanumérico de 6+ caracteres)
const extraer = (t) => {
  const txt = t.toUpperCase().replace(/\b([A-Z]{4})\s(\d{7})\b/g, '$1$2');
  return [...new Set(txt.split(/[\s,;|\t]+/).map((x) => x.replace(/[^A-Z0-9-]/g, '')).filter((x) => x.length >= 6 && /\d/.test(x)))];
};
const esCnt = (x) => /^[A-Z]{4}\d{7}$/.test(x);

export default function Cotizador() {
  const sp = useSearchParams();
  const [fecha, setFecha] = useState(sp.get('fecha') || manana());
  const [texto, setTexto] = useState(sp.get('bl') || '');
  const [usuario, setUsuario] = useState('');
  const [res, setRes] = useState([]);
  const [sel, setSel] = useState({});        // { cnt: { item: bool } }
  const [cant, setCant] = useState({});      // { cnt: { item: n } }
  const [estado, setEstado] = useState({});  // { cnt: {ok,msg,id} }
  const [cargando, setCargando] = useState(false);
  const [aviso, setAviso] = useState(null);

  useEffect(() => { try { setUsuario(localStorage.getItem('usuario') || ''); } catch {} }, []);
  useEffect(() => { try { localStorage.setItem('usuario', usuario); } catch {} }, [usuario]);

  const lista = useMemo(() => extraer(texto), [texto]);
  const nCnt = lista.filter(esCnt).length;

  async function cotizar() {
    if (!lista.length) return setAviso({ nivel: 'alto', mensaje: 'No se encontró ningún contenedor ni BL en el texto.' });
    setCargando(true); setAviso(null); setEstado({});
    try {
      const r = await fetch('/api/cotizar', { method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ entradas: lista, fecha }) }).then((x) => x.json());
      if (r.error) throw new Error(r.error);
      setRes(r.resultados);
      const s = {}, c = {};
      for (const x of r.resultados) if (x.ok) {
        s[x.contenedor] = Object.fromEntries(x.lineas.map((l) => [l.item, l.incluido]));
        c[x.contenedor] = Object.fromEntries(x.lineas.map((l) => [l.item, Number(l.cantidad)]));
      }
      setSel(s); setCant(c);
    } catch (e) { setAviso({ nivel: 'alto', mensaje: e.message }); }
    setCargando(false);
  }

  function calc(x) {
    const ls = x.lineas.map((l) => {
      const va = sel[x.contenedor]?.[l.item] ?? l.incluido;
      const q = l.opcional ? Number(cant[x.contenedor]?.[l.item] ?? l.cantidad) : Number(l.cantidad);
      const neto = r2(Number(l.tarifa) * q), igv = r2(neto * IGV);
      return { ...l, va: va && q > 0, q, neto, igv, total: r2(neto + igv) };
    });
    const t = ls.filter((l) => l.va).reduce((a, l) => ({ neto: a.neto + l.neto, igv: a.igv + l.igv, total: a.total + l.total }), { neto: 0, igv: 0, total: 0 });
    return { ls, t: { neto: r2(t.neto), igv: r2(t.igv), total: r2(t.total) } };
  }

  function ajustes(x) {
    const a = { incluir: [], excluir: [], cantidades: {} };
    for (const l of x.lineas) {
      const v = sel[x.contenedor]?.[l.item];
      if (l.opcional && v !== undefined && v !== l.incluido) (v ? a.incluir : a.excluir).push(l.item);
      const q = cant[x.contenedor]?.[l.item];
      if (l.opcional && q !== undefined && Number(q) !== Number(l.cantidad)) a.cantidades[l.item] = Number(q);
    }
    return a;
  }

  async function emitir(x) {
    setEstado((e) => ({ ...e, [x.contenedor]: { cargando: true } }));
    const r = await fetch('/api/emitir', { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ contenedor: x.contenedor, fecha, bl: x.json.servicio.bl, ajustes: ajustes(x), usuario: usuario || null }) })
      .then((y) => y.json());
    setEstado((e) => ({ ...e, [x.contenedor]: r.error ? { ok: false, msg: r.error } : { ok: true, id: r.liquidacion_id, version: r.version } }));
  }
  async function emitirTodo() {
    for (const x of res) if (x.ok && x.activa?.estado !== 'FACTURADA' && !estado[x.contenedor]?.ok) await emitir(x);
  }

  const grupos = useMemo(() => {
    const g = new Map();
    for (const x of res) {
      const k = x.ok ? x.json.servicio.bl : '';
      if (!g.has(k)) g.set(k, []);
      g.get(k).push(x);
    }
    return [...g.entries()];
  }, [res]);
  const totalLote = res.filter((x) => x.ok).reduce((a, x) => a + calc(x).t.total, 0);
  const listos = res.filter((x) => x.ok).length;

  return (
    <>
      <div className="card">
        <div className="row" style={{ marginBottom: 10 }}>
          <label className="f">Fecha de retiro<input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} /></label>
          <label className="f" style={{ marginLeft: 'auto' }}>Tu nombre (queda en la liquidación)
            <input value={usuario} onChange={(e) => setUsuario(e.target.value)} placeholder="Ej. Ana Torres" /></label>
        </div>
        <textarea value={texto} onChange={(e) => setTexto(e.target.value)}
          placeholder={'Pega contenedores o BL (uno por línea, o la tabla del correo tal cual).\nEj.: FFAU4896177   XIA1989243   276790232'} />
        <div className="row" style={{ marginTop: 10, justifyContent: 'space-between' }}>
          <span className="muted">{nCnt} contenedor(es) y {lista.length - nCnt} BL detectado(s){lista.length ? ': ' + lista.slice(0, 6).join(', ') + (lista.length > 6 ? '…' : '') : ''}</span>
          <button className="btn p" onClick={cotizar} disabled={cargando || !lista.length}>{cargando ? 'Cotizando…' : 'Cotizar'}</button>
        </div>
        {aviso && <div className={`alert ${aviso.nivel}`}>{aviso.mensaje}</div>}
      </div>

      {res.length > 0 && (
        <div className="card row" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
          <div><b>{listos}</b> de {res.length} contenedores listos · retiro {fmtFecha(fecha)}</div>
          <div className="row" style={{ alignItems: 'center' }}>
            <span className="tot">{usd(totalLote)}</span><span className="muted">total con IGV</span>
            <button className="btn p" onClick={emitirTodo} disabled={!listos}>Emitir todo a facturación</button>
          </div>
        </div>
      )}

      {grupos.map(([bl, items]) => (
        <div className="card bl" key={bl}>
          <div className="blhead">
            <h2 style={{ margin: 0 }}>{bl ? 'BL ' + bl : 'Sin datos en el DT'}</h2>
            <span className="muted">{items.length} contenedor(es)</span>
          </div>
          {items.map((x) => x.ok ? <Contenedor key={x.contenedor} x={x} c={calc(x)} sel={sel} setSel={setSel} cant={cant} setCant={setCant}
            st={estado[x.contenedor]} onEmitir={() => emitir(x)} /> : (
            <div className="cnt" key={x.contenedor}>
               <b className="mono">{x.contenedor}</b>
              <div className="alert alto">{x.error}</div>
              {x.isoValido === false && esCnt(x.contenedor) && <div className="alert medio">El número no pasa el dígito de control ISO 6346: revisa si está mal tipeado.</div>}
            </div>
          ))}
        </div>
      ))}
    </>
  );
}

function Contenedor({ x, c, sel, setSel, cant, setCant, st, onEmitir }) {
  const s = x.json.servicio;
  const facturada = x.activa?.estado === 'FACTURADA';
  const elegido = (l) => sel[x.contenedor]?.[l.item] ?? l.incluido;
  const visibles = c.ls.filter((l) => !l.opcional || elegido(l));
  const ocultas = c.ls.filter((l) => l.opcional && !elegido(l));
  const poner = (item, v) => setSel((o) => ({ ...o, [x.contenedor]: { ...o[x.contenedor], [item]: v } }));
  return (
    <div className="cnt">
      <div className="blhead">
        <div><b className="mono" style={{ fontSize: 15 }}>{s.contenedor}</b>{' '}
          <span className="pill tag">{s.tamano}' {s.clase}</span>{' '}
          <span className="pill tag">{s.tipo_carga}{s.clase_imo ? ' · ' + s.clase_imo : ''}</span>{' '}
          <span className="pill tag">{s.operador_portuario}</span></div>
        <div className="tot">{usd(c.t.total)}</div>
      </div>
      <div className="meta">
        <span>Ingreso <b>{fmtFecha(s.fecha_ingreso)}</b></span><span>Retiro <b>{fmtFecha(s.fecha_retiro)}</b></span>
        <span>Días <b>{s.dias_en_deposito}</b></span>
        <span>Línea <b>{s.linea_naviera || '—'}</b></span><span>Agencia <b>{s.agencia_aduana || '—'}</b></span>
        {x.json.acuerdo && <span>Acuerdo <b>{x.json.acuerdo.nombre}</b>{x.json.acuerdo.tipo === 'AGENCIA' ? ' (agencia)' : ''}</span>}
        <span>Factura a <b>{x.json.cliente.razon_social}</b>{x.json.cliente.ruc ? ' · RUC ' + x.json.cliente.ruc : ''}</span>
        {x.json.movilizaciones.length > 0 && <span>Movilizaciones <b>{x.json.movilizaciones.map((m) => m.operacion).join(', ')}</b></span>}
      </div>
      {x.json.alertas.map((a, i) => <div key={i} className={`alert ${a.nivel}`}>{a.mensaje}</div>)}
      {x.activa && <div className={`alert ${facturada ? 'alto' : 'medio'}`}>
        {facturada ? `Ya facturado (factura ${x.activa.factura_numero}). Para volver a liquidar, anula primero la liquidación.`
          : `Ya existe la liquidación LQ-${String(x.activa.id).padStart(6, '0')} v${x.activa.version} pendiente de facturar. Si emites, la reemplaza.`}
        {' '}<Link href={`/liquidacion/${x.activa.id}`}>Ver</Link></div>}
      <div className="tw"><table>
        <thead><tr><th></th><th>Rubro</th><th>Concepto</th><th className="n">Tarifa</th><th className="n">Cant.</th><th className="n">Neto</th><th className="n">IGV</th><th className="n">Total</th></tr></thead>
        <tbody>{visibles.map((l) => (
          <tr key={l.item}>
            <td>{l.opcional
              ? <button className="quitar" title="Quitar" onClick={() => poner(l.item, false)}>✕</button>
              : <span title="Automático según tarifario" style={{ color: 'var(--brand)' }}>✓</span>}</td>
            <td className="mono">{l.codigo_rubro ?? '—'}</td>
            <td className="c">{l.concepto}{l.origen !== 'TARIFARIO' && <> <span className="pill tag">{l.origen === 'MANUAL' ? 'adicional' : 'puerto'}</span></>}
              {l.nota && l.origen === 'SERV_ADICIONAL' && <div className="muted" style={{ fontSize: 12 }}>{l.nota}</div>}</td>
            <td className="n">{usd(l.tarifa)}</td>
            <td className="n">{l.origen === 'MANUAL' ? <input className="qty" type="number" min="1" step="1" value={cant[x.contenedor]?.[l.item] ?? l.cantidad}
              onChange={(e) => setCant((o) => ({ ...o, [x.contenedor]: { ...o[x.contenedor], [l.item]: e.target.value } }))} /> : Number(l.cantidad)}</td>
            <td className="n">{usd(l.neto)}</td><td className="n">{usd(l.igv)}</td><td className="n">{usd(l.total)}</td>
          </tr>))}</tbody>
        <tfoot><tr><td colSpan={5}>Total</td><td className="n">{usd(c.t.neto)}</td><td className="n">{usd(c.t.igv)}</td><td className="n">{usd(c.t.total)}</td></tr></tfoot>
      </table></div>
      {ocultas.length > 0 && <div className="agregar">
        <select value="" onChange={(e) => e.target.value && poner(Number(e.target.value), true)}>
          <option value="">+ Agregar adicional…</option>
          {ocultas.map((l) => <option key={l.item} value={l.item}>{l.concepto} — {usd(l.tarifa)}{l.unidad === 'HORA' ? ' / hora' : l.unidad === 'NOCHE' ? ' / noche' : ''}</option>)}
        </select>
      </div>}
      <div className="row" style={{ justifyContent: 'flex-end', marginTop: 8 }}>
        {st?.ok && <span className="alert ok" style={{ margin: 0 }}>Emitida <Link href={`/liquidacion/${st.id}`}>LQ-{String(st.id).padStart(6, '0')}</Link> (v{st.version})</span>}
        {st?.ok === false && <span className="alert alto" style={{ margin: 0 }}>{st.msg}</span>}
        <button className="btn p" onClick={onEmitir} disabled={facturada || st?.cargando || st?.ok}>
          {st?.cargando ? 'Emitiendo…' : st?.ok ? 'Emitida' : 'Emitir a facturación'}</button>
      </div>
    </div>
  );
}
