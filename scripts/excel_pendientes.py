"""Excel de contenedores pendientes del DT, con sugerencias tomadas de Movilizaciones, Serv Adicionales y Programación."""
import csv, re, sys, datetime as dt
from collections import defaultdict
from openpyxl import load_workbook, Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.comments import Comment
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.utils import get_column_letter

ENTRADA, MOV, SA, PROG, SALIDA = sys.argv[1:6]
ws_in = load_workbook(ENTRADA, data_only=True)['DT']
rows = list(ws_in.iter_rows(values_only=True)); head = list(rows[0])
data = [dict(zip(head, r)) for r in rows[1:] if any(v not in (None, '') for v in r)]
REQ = ['clase_cnt', 'tamano_cnt', 'tipo_carga', 'fecha_ingreso_balanza', 'operador_portuario', 'conexion', 'cliente']
completos = {(str(d['bk']).strip().upper(), str(d['contenedor']).strip().upper()) for d in data
             if all(d.get(c) not in (None, '') for c in REQ)}
pend = []
vistos = set()
for d in data:
    c = str(d.get('contenedor') or '').strip().upper(); b = str(d.get('bk') or '').strip().upper()
    if not re.match(r'^[A-Z]{4}\d{7}$', c) or (b, c) in completos or (b, c) in vistos or c.startswith('TSTU'):
        continue
    if any(d.get(x) in (None, '') for x in REQ):
        vistos.add((b, c)); pend.append(d)

mov = defaultdict(list)
for r in csv.DictReader(open(MOV, encoding='utf-8')):
    mov[(r.get('CTN') or '').strip().upper()].append((r.get('TIPO') or '').strip().upper())
sa = defaultdict(set)
for r in csv.DictReader(open(SA, encoding='utf-8')):
    p = (r.get('PROVEEDOR') or '').strip().upper()
    if p.startswith('APM'): sa[(r.get('Contenedor') or '').strip().upper()].add('APM')
    elif p in ('DPW', 'DPWC'): sa[(r.get('Contenedor') or '').strip().upper()].add('DPW')
prog = {}
for r in csv.DictReader(open(PROG, encoding='utf-8')):
    c = (r.get('CONTAINER') or '').strip().upper()
    if c: prog[c] = {'linea': (r.get('LINEA') or '').strip(), 'retiro': (r.get('RETIRO') or '').strip(), 'sem': r.get('SEM')}

def retiro_fecha(p):
    m = re.match(r'(\d{1,2})/(\d{1,2})/(\d{4})', p.get('retiro', '') or '')
    if not m: return None
    a, b, y = map(int, m.groups())
    cands = []
    for mo, da in ((b, a), (a, b)):
        try: cands.append(dt.date(y, mo, da))
        except ValueError: pass
    if not cands: return None
    sem = int(p['sem']) if str(p.get('sem', '')).isdigit() else None
    return min(cands, key=lambda x: abs(x.isocalendar()[1] - sem)) if sem else cands[0]

SUG = PatternFill('solid', fgColor='FFF2CC'); FALTA = PatternFill('solid', fgColor='FCE4D6')
VERDE = '009739'
COLS = head
wb = Workbook(); ws = wb.active; ws.title = 'DT'
for j, c in enumerate(COLS, 1):
    cell = ws.cell(row=1, column=j, value=c)
    cell.font = Font(bold=True, color='FFFFFF' if c in REQ + ['tipo_servicio', 'bk', 'contenedor', 'cliente'] else '1D2B23')
    cell.fill = PatternFill('solid', fgColor=VERDE if c in REQ + ['tipo_servicio', 'bk', 'contenedor', 'cliente'] else 'EEF2EF')
    ws.column_dimensions[get_column_letter(j)].width = max(12, min(28, len(c) + 4))
extra = len(COLS) + 1
ws.cell(row=1, column=extra, value='retiro_programado (referencia)').font = Font(bold=True, italic=True)
ws.column_dimensions[get_column_letter(extra)].width = 26

for d in pend:
    c = str(d['contenedor']).strip().upper(); p = prog.get(c, {})
    d['_retiro'] = retiro_fecha(p) if p else None
pend.sort(key=lambda d: d['_retiro'] or dt.date(1900, 1, 1), reverse=True)

n_sug = 0
for i, d in enumerate(pend, 2):
    c = str(d['contenedor']).strip().upper()
    sug = {}
    tipos = [t for t in mov.get(c, []) if re.search(r'(20|40)', t)]
    if tipos:
        t = tipos[-1]; tam = 40 if '40' in t else 20
        clase = 'HC' if 'HC' in t else 'RH' if ('RH' in t or 'RF' in t) else 'ST'
        sug['tamano_cnt'] = (tam, 'Control Movilizaciones: ' + t); sug['clase_cnt'] = (clase, 'Control Movilizaciones: ' + t)
        sug['isotype'] = (f'{tam}{clase}', 'Derivado de tamaño + clase')
    if len(sa.get(c, ())) == 1:
        sug['operador_portuario'] = (next(iter(sa[c])), 'Servicios adicionales: proveedor del puerto')
    if str(d.get('tipo_carga') or '').upper() == 'DRY':
        sug['conexion'] = ('false', 'Carga DRY: sin conexión reefer')
    if prog.get(c, {}).get('linea') and prog[c]['linea'] not in ('-', ''):
        sug['linea_maritima'] = (prog[c]['linea'], 'Programación del cliente')
    for j, col in enumerate(COLS, 1):
        v = d.get(col)
        cell = ws.cell(row=i, column=j)
        if v in (None, '') and col in sug:
            cell.value = sug[col][0]; cell.fill = SUG; cell.comment = Comment('Sugerido: ' + sug[col][1], 'Cotizador'); n_sug += 1
        else:
            if isinstance(v, dt.datetime): v = v.date()
            cell.value = v
            if v in (None, '') and col in REQ: cell.fill = FALTA
        if col == 'fecha_ingreso_balanza': cell.number_format = 'DD/MM/YYYY'
        if col in ('ruc_cliente',): cell.number_format = '0'
    if d['_retiro']:
        rc = ws.cell(row=i, column=extra, value=d['_retiro']); rc.number_format = 'DD/MM/YYYY'; rc.font = Font(italic=True, color='5F6F66')

listas = {'clase_cnt': 'ST,HC,RH,OT', 'tamano_cnt': '20,40', 'isotype': '20ST,40ST,40HC,20RH,40RH,20OT,40OT',
          'tipo_carga': 'DRY,REFRIGERADA,IMO', 'operador_portuario': 'APM,DPW', 'conexion': 'true,false',
          'clase_imo': 'Clase 1,Clase 2,Clase 3,Clase 4,Clase 5.1,Clase 5.2,Clase 6.1,Clase 6.2,Clase 7,Clase 8,Clase 9'}
for j, col in enumerate(COLS, 1):
    if col in listas:
        dv = DataValidation(type='list', formula1=f'"{listas[col]}"', allow_blank=True)
        ws.add_data_validation(dv); L = get_column_letter(j); dv.add(f'{L}2:{L}1000')
ws.freeze_panes = 'D2'; ws.auto_filter.ref = f'A1:{get_column_letter(extra)}{len(pend)+1}'

ins = wb.create_sheet('Instrucciones')
txt = ['Contenedores que están en la data del DT pero aún no cotizan porque les falta información.',
       'Naranja = falta y hay que llenarlo (sobre todo la FECHA DE INGRESO, que no se puede deducir).',
       'Amarillo = sugerido automáticamente (pasa el mouse para ver de dónde salió). Revísalo y corrígelo si no es así.',
       'La columna "retiro_programado" es solo referencia para priorizar: están ordenados del retiro más reciente al más antiguo.',
       'Cuando completes filas, sube este mismo archivo en Cargar datos → Data del DT. Las filas completas pasan a cotizar; las incompletas siguen en pendientes.',
       'No hace falta llenar todo de una vez: puedes subirlo las veces que quieras.']
ins['A1'] = 'Pendientes de la data del DT'; ins['A1'].font = Font(bold=True, size=14, color=VERDE)
for k, t in enumerate(txt, 3): ins.cell(row=k, column=1, value='• ' + t)
ins.column_dimensions['A'].width = 130
wb.save(SALIDA)
print('pendientes', len(pend), 'celdas sugeridas', n_sug,
      'con tamaño/clase', sum(1 for d in pend if mov.get(str(d['contenedor']).upper())),
      'con puerto', sum(1 for d in pend if len(sa.get(str(d['contenedor']).upper(), ())) == 1))
