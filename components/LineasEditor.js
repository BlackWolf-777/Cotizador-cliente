'use client';
import { usd, r2 } from '@/lib/format';

const IGV = 0.18;
export const AJUSTES_VACIOS = { incluir: [], excluir: [], cantidades: {}, tarifas: {} };
const POR = { HORA: ' / hora', VUELTA: ' / vuelta', BL: ' / BL', DIA: ' / día', NOCHE: ' / noche' };

// Misma regla que liq.aplicar_ajustes en la base de datos
export function calcular(lineas, a) {
  const ls = lineas.map((l) => {
    const va = l.opcional && a.excluir.includes(l.item) ? false : l.opcional && a.incluir.includes(l.item) ? true : l.incluido;
    const q = l.editable && a.cantidades[l.item] !== undefined && a.cantidades[l.item] !== '' ? Math.max(0, Number(a.cantidades[l.item])) : Number(l.cantidad);
    const t = l.origen === 'MANUAL' && a.tarifas[l.item] !== undefined && a.tarifas[l.item] !== '' ? Math.max(0, Number(a.tarifas[l.item])) : Number(l.tarifa);
    const neto = r2(t * q), igv = r2(neto * IGV);
    return { ...l, va: va && q > 0, elegido: va, q, t, neto, igv, total: r2(neto + igv) };
  });
  const sum = (k) => r2(ls.filter((l) => l.va).reduce((s, l) => s + l[k], 0));
  return { ls, t: { neto: sum('neto'), igv: sum('igv'), total: sum('total') } };
}

// Ajustes limpios para enviar al servidor
export function limpiar(a) {
  const n = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== '' && v !== undefined).map(([k, v]) => [k, Number(v)]));
  return { incluir: a.incluir, excluir: a.excluir, cantidades: n(a.cantidades), tarifas: n(a.tarifas) };
}

export default function LineasEditor({ lineas, ajustes, setAjustes, compacto = false }) {
  const { ls, t } = calcular(lineas, ajustes);
  const visibles = ls.filter((l) => l.elegido);
  const ocultas = ls.filter((l) => !l.elegido && l.opcional);
  const poner = (item, v) => setAjustes((a) => {
    const base = lineas.find((l) => l.item === item);
    const inc = a.incluir.filter((x) => x !== item), exc = a.excluir.filter((x) => x !== item);
    if (v !== base.incluido) (v ? inc : exc).push(item);
    return { ...a, incluir: inc, excluir: exc };
  });
  const setNum = (campo, item, v) => setAjustes((a) => ({ ...a, [campo]: { ...a[campo], [item]: v } }));

  return (
    <>
      <div className="tw"><table>
        <thead><tr><th></th><th>Rubro</th><th>Concepto</th><th className="n">Tarifa</th><th className="n">Cant.</th><th className="n">Neto</th><th className="n">IGV</th><th className="n">Total</th></tr></thead>
        <tbody>{visibles.map((l) => (
          <tr key={l.item} className={l.va ? '' : 'off'}>
            <td>{l.opcional
              ? <button className="quitar" title="Quitar" onClick={() => poner(l.item, false)}>✕</button>
              : <span title="Automático según tarifario" style={{ color: 'var(--brand)' }}>✓</span>}</td>
            <td className="mono">{l.codigo_rubro ?? '—'}</td>
            <td className="c">{l.concepto}{l.origen === 'MANUAL' && <> <span className="pill tag">adicional</span></>}
              {!compacto && l.nota && <div className="muted" style={{ fontSize: 12 }}>{l.nota}</div>}</td>
            <td className="n">{l.origen === 'MANUAL'
              ? <input className="qty" style={{ width: 80 }} type="number" min="0" step="0.01" value={ajustes.tarifas[l.item] ?? l.tarifa}
                  onChange={(e) => setNum('tarifas', l.item, e.target.value)} />
              : usd(l.t)}</td>
            <td className="n">{l.editable
              ? <input className="qty" type="number" min="0" step="0.5" value={ajustes.cantidades[l.item] ?? Number(l.cantidad)}
                  onChange={(e) => setNum('cantidades', l.item, e.target.value)} />
              : Number(l.cantidad)}</td>
            <td className="n">{usd(l.neto)}</td><td className="n">{usd(l.igv)}</td><td className="n">{usd(l.total)}</td>
          </tr>))}</tbody>
        <tfoot><tr><td colSpan={5}>Total USD</td><td className="n">{usd(t.neto)}</td><td className="n">{usd(t.igv)}</td><td className="n">{usd(t.total)}</td></tr></tfoot>
      </table></div>
      {ocultas.length > 0 && <div className="agregar">
        <select value="" onChange={(e) => e.target.value && poner(Number(e.target.value), true)}>
          <option value="">+ Agregar…</option>
          {ocultas.map((l) => <option key={l.item} value={l.item}>{l.concepto}{l.origen === 'MANUAL' ? ` — ${usd(l.tarifa)}${POR[l.unidad] || ''}` : ` — ${usd(l.t)}`}</option>)}
        </select>
      </div>}
    </>
  );
}
