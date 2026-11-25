import { q } from '@/lib/db';
import Cargador from './Cargador';
import { fechaHora } from '@/lib/format';

export const dynamic = 'force-dynamic';

export default async function Cargar() {
  const hist = await q(`SELECT id, tipo, archivo, filas, aceptadas, rechazadas, creado_por, creado_en FROM ops.importacion
    WHERE tipo <> 'PROGRAMACION' ORDER BY id DESC LIMIT 15`);
  return (
    <>
      <h1>Cargar datos</h1>
      <p className="sub">Sube el Excel (.xlsx) o CSV tal como lo descargas. Cada carga reemplaza a la anterior de esa fuente y queda registrada.</p>
      {process.env.DEMO_MODE === '1'
        ? <div className="alert medio">En la demo pública la carga de archivos está desactivada para proteger los datos de ejemplo.
            Los archivos con el formato esperado están en la carpeta <code>datos_demo/</code> del repositorio; puedes probar la carga ejecutando el proyecto en local.</div>
        : <Cargador />}
      <div className="card tw">
        <h2>Cargas anteriores</h2>
        <table><thead><tr><th>#</th><th>Fuente</th><th>Archivo</th><th className="n">Filas</th><th className="n">Válidas</th><th className="n">Rechazadas</th><th>Fecha</th></tr></thead>
          <tbody>{hist.map((h) => <tr key={h.id}><td>{h.id}</td><td>{h.tipo.replace('_', ' ')}</td><td>{h.archivo}</td><td className="n">{h.filas}</td>
            <td className="n">{h.aceptadas}</td><td className="n">{h.rechazadas}</td><td className="muted">{fechaHora(h.creado_en)}{h.creado_por ? ' · ' + h.creado_por : ''}</td></tr>)}</tbody></table>
      </div>
    </>
  );
}
