import { q } from '@/lib/db';
import { usd, fecha } from '@/lib/format';

export const dynamic = 'force-dynamic';
const DISP = {
  SIEMPRE: 'Siempre', CONEXION: 'Reefer conectado', DPW: 'Vía DPW', IMO: 'Carga IMO', CUADRILLA: 'Por movilización con cuadrilla',
  MONTACARGA: 'Por movilización con montacargas', MANIPULEO: 'Por posicionamiento (reach stacker)', SINI: 'Por traslado a SINI',
  ALMACENAJE: 'Por día pasado los días libres', RECUPERO_ADMIN: 'Si se refactura un sobrecosto de puerto', MANUAL: 'Opcional (lo marca el ejecutivo)',
  CS_INGRESO: 'Por ingreso de carga terrestre', CS_TRANSPORTE: 'Vueltas de transporte (2 por defecto)',
  CS_MONTACARGA: 'Horas al recibir × 2 (recepción + despacho)', CS_CUADRILLA: 'Horas al recibir × 2 (recepción + despacho)',
};

export default async function Tarifario() {
  const tars = await q(`SELECT t.*, c.razon_social, c.ruc, c.tipo AS tipo_parte FROM tarifas.tarifario t JOIN core.cliente c ON c.id = t.cliente_id ORDER BY c.razon_social, t.vigente_desde DESC`);
  const reglas = await q(`SELECT * FROM tarifas.regla WHERE activo ORDER BY tarifario_id, orden, codigo_rubro NULLS LAST, puerto, tamano, grupo_imo`);
  const rec = await q(`SELECT * FROM tarifas.recupero_concepto ORDER BY tratamiento, concepto`);
  const per = await q(`SELECT * FROM tarifas.cs_periodo ORDER BY tarifario_id, periodo`);
  return (
    <>
      <h1>Tarifario</h1>
      <p className="sub">Reglas que usa el cotizador. Las marcadas en naranja tienen un dato pendiente de confirmar con comercial.</p>
      {tars.map((t) => {
        const rs = reglas.filter((r) => r.tarifario_id === t.id);
        return (
          <div className="card" key={t.id}>
            <div className="blhead"><h2 style={{ margin: 0 }}>{t.razon_social}{t.tipo_parte === 'AGENCIA' ? ' (agencia de aduana)' : ''} · {t.nombre}</h2>
              <span className="muted">Vigente desde {fecha(t.vigente_desde)}{t.vigente_hasta ? ' hasta ' + fecha(t.vigente_hasta) : ''} · {t.dias_libres} días libres</span></div>
            <p className="muted" style={{ marginTop: 0 }}>Código {t.codigo} · RUC {t.ruc ?? 'pendiente'}{t.documento ? ' · ' + t.documento : ''}</p>
            {t.operacion === 'CARGA_SUELTA' && <div className="tw" style={{ marginBottom: 12 }}>
              <b>Almacenaje mensual de carga en almacén</b> <span className="muted">(los periodos se reinician cada mes; umbral {Number(t.umbral_kg).toLocaleString('es-PE')} kg)</span>
              <table style={{ marginTop: 6 }}><thead><tr><th>Rubro</th><th>Periodo</th><th>Días del mes cobrados</th><th className="n">Menos de 1 TN (por día)</th><th className="n">1 TN o más (por día y TN)</th></tr></thead>
                <tbody>{per.filter((p) => p.tarifario_id === t.id).map((p) => (<tr key={p.periodo}><td className="mono">{p.codigo_rubro}</td><td>Periodo {p.periodo}</td>
                  <td>{p.dia_desde} a {p.dia_hasta ?? 'fin de mes'}</td><td className="n">{usd(p.tarifa_menor)}</td><td className="n">{usd(p.tarifa_mayor)}</td></tr>))}</tbody></table>
              <p className="muted" style={{ fontSize: 12 }}>Carga terrestre en depósito simple: {t.dias_libres} días libres. La tarifa de almacenaje posterior no está definida (alerta al cotizar).</p>
              <b>Servicios de carga suelta</b></div>}
            <div className="tw"><table>
              <thead><tr><th>Rubro</th><th>Concepto</th><th>Puerto</th><th>Carga</th><th>Tam.</th><th>IMO</th><th>Se aplica</th><th>Unidad</th><th>Factura</th><th className="n">Monto</th></tr></thead>
              <tbody>{rs.map((r) => (
                <tr key={r.id} style={r.pendiente ? { background: 'var(--warn-bg)' } : undefined}>
                  <td className="mono">{r.codigo_rubro ?? '—'}</td>
                  <td>{r.concepto}{r.pendiente && <div style={{ fontSize: 12, color: 'var(--warn)' }}>{r.pendiente}</div>}</td>
                  <td>{r.puerto}</td><td>{r.tipo_carga}</td><td>{r.tamano}</td><td>{r.grupo_imo || ''}</td>
                  <td className="muted">{DISP[r.disparador]}</td><td className="muted">{r.unidad.toLowerCase()}</td><td>{r.unidad_negocio}</td>
                  <td className="n">{usd(r.monto)}</td></tr>))}</tbody></table></div>
          </div>
        );
      })}
      <div className="card">
        <h2>Sobrecostos del puerto (Serv Adicionales)</h2>
        <p className="muted" style={{ marginTop: 0 }}>Cómo se trata cada concepto que APM/DPW le cobra al depósito. Lo que no está en la lista se propone para refacturar al cliente más el gasto administrativo.</p>
        <table><thead><tr><th>Concepto del puerto</th><th>Tratamiento</th><th>Nota</th></tr></thead>
          <tbody>{rec.map((r) => <tr key={r.concepto}><td>{r.concepto}</td><td><span className="pill tag">{r.tratamiento.replace('_', ' ')}</span></td><td className="muted">{r.nota}</td></tr>)}</tbody></table>
      </div>
    </>
  );
}
