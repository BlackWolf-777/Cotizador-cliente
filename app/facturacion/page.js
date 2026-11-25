import Link from 'next/link';
import { q } from '@/lib/db';
import { usd, fecha, fechaHora } from '@/lib/format';
import DescargarLote from './DescargarLote';

export const dynamic = 'force-dynamic';

export default async function Facturacion() {
  const rows = await q(`SELECT l.id, l.bl, l.contenedor, l.fecha_retiro, l.version, l.total, l.emitido_en, l.emitido_por, l.origen,
      l.tipo, coalesce(l.facturar_razon, c.razon_social) cliente, CASE WHEN c.tipo = 'AGENCIA' THEN c.nombre_corto END acuerdo, jsonb_array_length(l.json->'lineas') nlin
    FROM liq.liquidacion l JOIN core.cliente c ON c.id = l.cliente_id
    WHERE l.estado = 'EMITIDA' ORDER BY l.fecha_retiro, l.bl, l.contenedor`);
  const total = rows.reduce((a, r) => a + Number(r.total), 0);
  return (
    <>
      <h1>Por facturar</h1>
      <p className="sub">Bandeja de facturación: cada liquidación trae su paquete JSON con rubros, tarifas y totales. Al emitir la factura, registra su número.</p>
      <div className="card row" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
        <div><b>{rows.length}</b> liquidaciones pendientes · <b>{usd(total)}</b> con IGV</div>
        <DescargarLote ids={rows.map((r) => r.id)} />
      </div>
      <div className="card tw">
        {rows.length === 0 ? <div className="empty">No hay liquidaciones pendientes de facturar.</div> :
          <table><thead><tr><th>Liquidación</th><th>Factura a</th><th>BL</th><th>Contenedor</th><th>Retiro</th><th className="n">Conceptos</th><th className="n">Total</th><th>Emitida</th><th></th></tr></thead>
            <tbody>{rows.map((r) => (
              <tr key={r.id}><td className="mono"><Link href={`/liquidacion/${r.id}`}>LQ-{String(r.id).padStart(6, '0')}</Link>{r.version > 1 && <span className="muted"> v{r.version}</span>}
                {r.origen === 'PRUEBA' && <> <span className="pill tag">prueba</span></>}</td>
                <td>{r.cliente}{r.acuerdo && <div className="muted" style={{ fontSize: 11 }}>acuerdo {r.acuerdo}</div>}</td><td>{r.bl}</td><td>{r.tipo === 'FCL' ? <span className="mono">{r.contenedor}</span> : <span className="pill tag">{r.tipo === 'CS_MENSUAL' ? 'C/S mensual' : 'C/S depósito'}</span>}</td><td>{fecha(r.fecha_retiro)}</td>
                <td className="n">{r.nlin}</td><td className="n">{usd(r.total)}</td>
                <td className="muted">{fechaHora(r.emitido_en)}{r.emitido_por ? ' · ' + r.emitido_por : ''}</td>
                <td><Link className="btn sm" href={`/liquidacion/${r.id}`}>Abrir</Link></td></tr>))}</tbody></table>}
      </div>
    </>
  );
}
