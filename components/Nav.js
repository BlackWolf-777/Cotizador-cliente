'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const ITEMS = [
  ['/', 'Inicio'], ['/cotizar', 'Cotizar'], ['/carga-suelta', 'Carga suelta'], ['/facturacion', 'Por facturar'],
  ['/historial', 'Historial'], ['/tarifario', 'Tarifario'], ['/cargar', 'Cargar datos'],
];
export default function Nav() {
  const p = usePathname();
  return (
    <nav className="nav">
      {ITEMS.map(([href, label]) => (
        <Link key={href} href={href} className={(href === '/' ? p === '/' : p.startsWith(href)) ? 'on' : ''}>{label}</Link>
      ))}
    </nav>
  );
}
