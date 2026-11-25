import SubnavCS from '@/components/SubnavCS';
import Mensual from './Mensual';

export default function Page() {
  return (
    <>
      <h1>Liquidación mensual de almacenaje</h1>
      <p className="sub">Toda la carga en almacén con almacenaje activo, en una sola liquidación (rubro 801). Días por BL: del día siguiente al ingreso (o desde el 1) hasta la salida (o fin de mes).
        Periodos: 1–5, 6–10, 11–20 y 21 a fin de mes; desde 1 TN la tarifa es por tonelada.</p>
      <SubnavCS />
      <Mensual />
    </>
  );
}
