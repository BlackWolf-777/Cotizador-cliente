'use client';
import { useState } from 'react';

export default function Acceso() {
  const [clave, setClave] = useState('');
  const [err, setErr] = useState(null);
  async function entrar(e) {
    e.preventDefault();
    const r = await fetch('/api/acceso', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ clave }) });
    if (r.ok) window.location.href = '/'; else setErr('Clave incorrecta');
  }
  return (
    <form className="card" onSubmit={entrar} style={{ maxWidth: 360 }}>
      <h1>Acceso</h1><p className="sub">Ingresa la clave del piloto.</p>
      <input type="password" value={clave} onChange={(e) => setClave(e.target.value)} style={{ width: '100%' }} autoFocus />
      {err && <div className="alert alto">{err}</div>}
      <button className="btn p" style={{ marginTop: 10 }}>Entrar</button>
    </form>
  );
}
