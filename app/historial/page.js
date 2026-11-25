import Link from 'next/link';
import { q } from '@/lib/db';
import { usd, fecha, fechaHora } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function Historial({ searchParams }) {
  const sp = await searchParams;
  const texto = (sp.q || '').toUpperCase().trim();
  const est = sp.estado || '';
  const rows = await q(`SELECT l.id, l.bl, l.contenedor, l.fecha_retiro, l.version, l.estado, l.total, l.emitido_en, l.emitido_por,
      l.factura_numero, l.origen, l.tipo, coalesce(l.facturar_razon, c.razon_social) cliente, CASE WHEN c.tipo = 'AGENCIA' THEN c.nombre_corto END acuerdo
    FROM liq.liquidacion l JOIN core.cliente c ON c.id = l.cliente_id
    WHERE ($1 = '' OR l.bl ILIKE '%'||$1||'%' OR l.contenedor ILIKE '%'||$1||'%' OR l.factura_numero ILIKE '%'||$1||'%'
           OR ('LQ-'||lpad(l.id::text,6,'0')) ILIKE '%'||$1||'%')
      AND ($2 = '' OR l.estado = $2)
    ORDER BY l.emitido_en DESC LIMIT 300`, [texto, est]);
  return (
    <>
      <h1>Historial de liquidaciones</h1>
      <p className="sub">Todas las versiones quedan guardadas con su JSON y su huella digital (no se pueden editar).</p>
      <form className="card row">
        <label className="f">Buscar<input name="q" defaultValue={sp.q || ''} placeholder="BL, contenedor, factura, LQ- o ALMACEN CS" /></label>
        <label className="f">Estado<select name="estado" defaultValue={est}>
          <option value="">Todos</option><option>EMITIDA</option><option>FACTURADA</option><option>REEMPLAZADA</option><option>ANULADA</option></select></label>
        <button className="btn p">Filtrar</button>
      </form>
      <div className="card tw">
        {rows.length === 0 ? <div className="empty">Sin resultados.</div> :
          <table><thead><tr><th>Liquidación</th><th>Estado</th><th>Factura a</th><th>BL</th><th>Contenedor / tipo</th><th>Retiro</th><th className="n">Total</th><th>Factura</th><th>Emitida</th></tr></thead>
            <tbody>{rows.map((r) => (
              <tr key={r.id}><td className="mono"><Link href={`/liquidacion/${r.id}`}>LQ-{String(r.id).padStart(6, '0')}</Link> <span className="muted">v{r.version}</span>
                {r.origen === 'PRUEBA' && <> <span className="pill tag">prueba</span></>}</td>
                <td><span className={`pill ${r.estado}`}>{r.estado}</span></td><td>{r.cliente}{r.acuerdo && <div className="muted" style={{ fontSize: 11 }}>acuerdo {r.acuerdo}</div>}</td><td>{r.bl}</td>
                <td>{r.tipo === 'FCL' ? <span className="mono">{r.contenedor}</span> : <span className="pill tag">{r.tipo === 'CS_MENSUAL' ? 'C/S almacenaje mensual' : 'C/S depósito simple'}</span>}</td><td>{fecha(r.fecha_retiro)}</td><td className="n">{usd(r.total)}</td>
                <td className="mono">{r.factura_numero || '—'}</td><td className="muted">{fechaHora(r.emitido_en)}{r.emitido_por ? ' · ' + r.emitido_por : ''}</td></tr>))}</tbody></table>}
      </div>
    </>
  );
}
