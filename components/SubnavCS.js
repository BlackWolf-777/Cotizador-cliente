'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const ITEMS = [['/carga-suelta', 'Stock'], ['/carga-suelta/mensual', 'Liquidación mensual'], ['/carga-suelta/deposito', 'Carga terrestre']];
export default function SubnavCS() {
  const p = usePathname();
  return (
    <div className="row" style={{ marginBottom: 14 }}>
      {ITEMS.map(([h, l]) => <Link key={h} href={h} className={`btn sm ${p === h ? 'p' : ''}`}>{l}</Link>)}
    </div>
  );
}
