import './globals.css';
import Nav from '@/components/Nav';

export const metadata = { title: 'Cotizador DT', description: 'Cotizador y liquidaciones de un depósito temporal (demo con datos ficticios)' };

export default function RootLayout({ children }) {
  return (
    <html lang="es">
      <body>
        <div className="shell">
          <aside className="side">
            <div className="logo"><span>Cotizador</span> DT<small>Depósito temporal · demo</small></div>
            <div className="demo">Datos ficticios para demostración. La demo se reinicia cada día.</div>
            <Nav />
          </aside>
          <main className="main">{children}</main>
        </div>
      </body>
    </html>
  );
}
