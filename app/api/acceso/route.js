import { NextResponse } from 'next/server';

export async function POST(req) {
  const { clave } = await req.json();
  if (!process.env.APP_CLAVE || clave === process.env.APP_CLAVE) {
    const res = NextResponse.json({ ok: true });
    res.cookies.set('acceso', process.env.APP_CLAVE || 'abierto', { httpOnly: true, sameSite: 'lax', maxAge: 60 * 60 * 24 * 30, path: '/' });
    return res;
  }
  return NextResponse.json({ error: 'Clave incorrecta' }, { status: 401 });
}
