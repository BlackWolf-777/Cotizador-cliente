import { NextResponse } from 'next/server';
import { reiniciarDemo } from '@/lib/demo';

export const dynamic = 'force-dynamic';
export const maxDuration = 60;

// La llama el cron diario de Vercel (Authorization: Bearer CRON_SECRET) o manualmente con ?token=CRON_SECRET
export async function GET(req) {
  const secreto = process.env.CRON_SECRET;
  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '') || new URL(req.url).searchParams.get('token');
  if (!secreto || token !== secreto) return NextResponse.json({ error: 'No autorizado' }, { status: 401 });
  try {
    return NextResponse.json(await reiniciarDemo());
  } catch (e) {
    return NextResponse.json({ error: e.message }, { status: 500 });
  }
}
