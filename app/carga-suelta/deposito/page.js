import { Suspense } from 'react';
import SubnavCS from '@/components/SubnavCS';
import Deposito from './Deposito';

export default function Page() {
  return (
    <>
      <h1>Carga terrestre (depósito simple)</h1>
      <p className="sub">Servicio de terminal, transporte y los recursos que reportó operaciones al recibir (se propone el doble: recepción + despacho). 30 días libres.</p>
      <SubnavCS />
      <Suspense fallback={<div className="card">Cargando…</div>}><Deposito /></Suspense>
    </>
  );
}
