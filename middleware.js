import { NextResponse } from 'next/server';

// Protección de la aplicación:
//  * APP_CLAVE (opcional): pide una clave compartida para entrar, como en el piloto.
//  * DEMO_MODE=1: demo pública. Desactiva la carga de archivos, limita el tamaño de lo que se envía
//    y la cantidad de escrituras por visitante. Los datos se restauran cada día.
const LIMITE_BYTES = 32 * 1024;
const ESCRITURAS_POR_MINUTO = 40;
const visitas = new Map(); // ip -> { n, desde }  (por instancia; Vercel además filtra abuso a nivel de red)

function demasiadas(ip) {
  const ahora = Date.now();
  const v = visitas.get(ip);
  if (!v || ahora - v.desde > 60_000) { visitas.set(ip, { n: 1, desde: ahora }); return false; }
  v.n += 1;
  if (visitas.size > 5000) visitas.clear();
  return v.n > ESCRITURAS_POR_MINUTO;
}

export function middleware(req) {
  const { pathname } = req.nextUrl;
  const api = pathname.startsWith('/api/');

  if (process.env.DEMO_MODE === '1' && api && req.method !== 'GET') {
    if (pathname.startsWith('/api/importar')) {
      return NextResponse.json({ error: 'En la demo pública la carga de archivos está desactivada.' }, { status: 403 });
    }
    if (Number(req.headers.get('content-length') || 0) > LIMITE_BYTES) {
      return NextResponse.json({ error: 'Solicitud demasiado grande' }, { status: 413 });
    }
    const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'desconocida';
    if (demasiadas(ip)) return NextResponse.json({ error: 'Demasiadas operaciones seguidas. Intenta en un minuto.' }, { status: 429 });
  }

  const clave = process.env.APP_CLAVE;
  if (!clave) return NextResponse.next();
  if (pathname.startsWith('/acceso') || pathname.startsWith('/api/acceso') || pathname.startsWith('/api/demo/') || pathname.startsWith('/_next')) return NextResponse.next();
  if (req.cookies.get('acceso')?.value === clave) return NextResponse.next();
  if (api) return NextResponse.json({ error: 'No autorizado' }, { status: 401 });
  return NextResponse.redirect(new URL('/acceso', req.url));
}
export const config = { matcher: ['/((?!favicon.ico).*)'] };
