import { Suspense } from 'react';
import Cotizador from './Cotizador';

export default function Page() {
  return (
    <>
      <h1>Cotizar</h1>
      <p className="sub">Pega contenedores o BL. El sistema toma las características del contenedor de la data del DT, aplica el tarifario del acuerdo comercial (con el cliente o con su agencia de aduana),
        suma los costos del DT (Control Movilizaciones) y los del puerto (Servicios adicionales). Si algo no está en la data del DT, no se cotiza.</p>
      <Suspense fallback={<div className="card">Cargando…</div>}><Cotizador /></Suspense>
    </>
  );
}
