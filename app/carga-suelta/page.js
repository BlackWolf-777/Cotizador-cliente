import SubnavCS from '@/components/SubnavCS';
import Stock from './Stock';

export default function Page() {
  return (
    <>
      <h1>Carga suelta</h1>
      <p className="sub">Registro de la carga suelta en el almacén. Cada BL queda grabado hasta su salida; al salir no se borra, pasa al historial con fecha y motivo (retiro, destrucción o adjudicación SUNAT).</p>
      <SubnavCS />
      <Stock />
    </>
  );
}
