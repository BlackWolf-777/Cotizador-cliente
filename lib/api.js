import { NextResponse } from 'next/server';
import { errorMsg } from './db';

export function ok(data) { return NextResponse.json(data); }
export function fail(e, status = 400) { return NextResponse.json({ error: errorMsg(e) }, { status }); }
