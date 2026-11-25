import Link from 'next/link';
import { q } from '@/lib/db';
import { usd, fecha, fechaHora } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function Inicio() {
  let k, pend, alertas, cargas, err;
  try {
    [k] = await q(`SELECT
        count(*) FILTER (WHERE estado = 'EMITIDA') pend, coalesce(sum(total) FILTER (WHERE estado = 'EMITIDA'),0) pend_m,
        count(*) FILTER (WHERE estado = 'FACTURADA' AND date_trunc('month', facturado_en) = date_trunc('month', now())) fac,
        coalesce(sum(total) FILTER (WHERE estado = 'FACTURADA' AND date_trunc('month', facturado_en) = date_trunc('month', now())),0) fac_m,
        count(*) FILTER (WHERE emitido_en::date = current_date) hoy
      FROM liq.liquidacion WHERE origen = 'REAL'`);
    pend = await q(`SELECT bl, count(*) n, min(fecha_ingreso_balanza) ingreso, max(dias_en_deposito) dias
      FROM liq.v_contenedor_pendiente GROUP BY bl ORDER BY min(fecha_ingreso_balanza) LIMIT 10`);
    alertas = await q(`SELECT * FROM liq.v_contenedor_pendiente WHERE dias_en_deposito >= 25 ORDER BY dias_en_deposito DESC LIMIT 8`);
    cargas = await q(`SELECT DISTINCT ON (tipo) tipo, archivo, aceptadas, rechazadas, creado_en FROM ops.importacion ORDER BY tipo, creado_en DESC`);
  } catch (e) { err = e.message; }

  if (err) return (<><h1>Inicio</h1><div className="alert alto">No hay conexión con la base de datos: {err}</div></>);

  return (
    <>
      <h1>Inicio</h1>
      <p className="sub">Resumen de liquidaciones y de los contenedores del DT.</p>
      <div className="grid kpis">
        <div className="card kpi"><div className="l">Por facturar</div><div className="v">{k.pend}</div><div className="s">{usd(k.pend_m)} con IGV</div></div>
        <div className="card kpi"><div className="l">Facturadas este mes</div><div className="v">{k.fac}</div><div className="s">{usd(k.fac_m)} con IGV</div></div>
        <div className="card kpi"><div className="l">Emitidas hoy</div><div className="v">{k.hoy}</div><div className="s"><Link href="/cotizar">Cotizar ahora →</Link></div></div>
      </div>
      <div className="two">
        <div className="card">
          <h2>En el DT sin liquidar</h2>
          {pend.length === 0 ? <p className="muted">Todos los contenedores del DT tienen liquidación.</p> :
            <table><thead><tr><th>BL</th><th className="n">Contenedores</th><th>Ingreso</th><th></th></tr></thead><tbody>{pend.map((p) => (
              <tr key={p.bl}><td>{p.bl}</td><td className="n">{p.n}</td><td>{fecha(p.ingreso)}</td>
                <td className="n"><Link href={`/cotizar?bl=${encodeURIComponent(p.bl)}`}>Cotizar →</Link></td></tr>))}
            </tbody></table>}
        </div>
        <div className="card">
          <h2>Cerca de vencer los días libres</h2>
          {alertas.length === 0 ? <p className="muted">Ningún contenedor sin liquidar supera los 25 días en el depósito.</p> :
            <table><thead><tr><th>Contenedor</th><th>BL</th><th className="n">Días</th></tr></thead><tbody>
              {alertas.map((a) => (<tr key={a.bl + a.contenedor}><td className="mono">{a.contenedor}</td><td>{a.bl}</td>
                <td className="n"><span className={`pill ${a.dias_en_deposito > 30 ? 'EMITIDA' : 'tag'}`}>{a.dias_en_deposito}</span></td></tr>))}
            </tbody></table>}
        </div>
      </div>
      <div className="card">
        <h2>Últimas cargas de datos</h2>
        {cargas.length === 0 ? <p className="muted">Aún no se cargó ningún archivo. <Link href="/cargar">Cargar datos</Link></p> :
          <table><thead><tr><th>Fuente</th><th>Archivo</th><th className="n">Filas válidas</th><th className="n">Rechazadas</th><th>Fecha</th></tr></thead>
            <tbody>{cargas.map((c) => (<tr key={c.tipo}><td>{c.tipo.replace('_', ' ')}</td><td>{c.archivo}</td>
              <td className="n">{c.aceptadas}</td><td className="n">{c.rechazadas}</td><td>{fechaHora(c.creado_en)}</td></tr>))}</tbody></table>}
      </div>
    </>
  );
}
