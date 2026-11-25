import { NextResponse } from 'next/server';

// Si APP_CLAVE está definida, se pide una clave compartida para entrar (piloto).
export function middleware(req) {
  const clave = process.env.APP_CLAVE;
  if (!clave) return NextResponse.next();
  const { pathname } = req.nextUrl;
  if (pathname.startsWith('/acceso') || pathname.startsWith('/api/acceso') || pathname.startsWith('/_next')) return NextResponse.next();
  if (req.cookies.get('acceso')?.value === clave) return NextResponse.next();
  if (pathname.startsWith('/api/')) return NextResponse.json({ error: 'No autorizado' }, { status: 401 });
  return NextResponse.redirect(new URL('/acceso', req.url));
}
export const config = { matcher: ['/((?!favicon.ico).*)'] };
