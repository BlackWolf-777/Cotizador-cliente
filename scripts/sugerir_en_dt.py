"""Completa con sugerencias (en amarillo, con comentario) la propia Data DT del usuario, sin tocar lo que ya llenó.
Uso: python3 scripts/sugerir_en_dt.py DATA_DT.xlsx movilizaciones.csv serv_adicionales.csv SALIDA.xlsx"""
import csv, re, sys, datetime as dt
from collections import defaultdict
from openpyxl import load_workbook
from openpyxl.styles import PatternFill, Font
from openpyxl.comments import Comment

ENT, MOV, SA, SAL = sys.argv[1:5]
wb = load_workbook(ENT); ws = wb['DT']
head = [str(c.value).strip() if c.value else '' for c in ws[1]]
col = {h: i + 1 for i, h in enumerate(head) if h}
REQ = ['clase_cnt', 'tamano_cnt', 'tipo_carga', 'fecha_ingreso_balanza', 'operador_portuario', 'conexion', 'cliente']
fmov = lambda s: dt.datetime.strptime(s.strip(), '%m/%d/%Y').date()
mov = defaultdict(list)
for r in csv.DictReader(open(MOV, encoding='utf-8', errors='ignore')):
    try: mov[(r.get('CTN') or '').strip().upper()].append((fmov(r['FECHA']), (r.get('TIPO') or '').strip().upper(), (r.get('OPERACION') or '').strip()))
    except Exception: pass
sa = defaultdict(set); sa_f = {}
for r in csv.DictReader(open(SA, encoding='utf-8', errors='ignore')):
    c = (r.get('Contenedor') or '').strip().upper(); p = (r.get('PROVEEDOR') or '').strip().upper()
    if p.startswith('APM'): sa[c].add('APM')
    elif p.startswith('DPW'): sa[c].add('DPW')
SUG = PatternFill('solid', fgColor='FFF2CC'); FALTA = PatternFill('solid', fgColor='FCE4D6')
ref = ws.max_column + 1
ws.cell(row=1, column=ref, value='primera_movilizacion (referencia)').font = Font(bold=True, italic=True)
ws.column_dimensions[ws.cell(row=1, column=ref).column_letter].width = 44
n = {'filas': 0, 'puerto': 0, 'conexion': 0, 'referencia': 0}
for i in range(2, ws.max_row + 1):
    g = lambda h: ws.cell(row=i, column=col[h]).value
    c = str(g('contenedor') or '').strip().upper()
    if not re.fullmatch(r'[A-Z]{4}\d{7}', c): continue
    if all(g(h) not in (None, '') for h in REQ): continue
    n['filas'] += 1
    def poner(h, v, por):
        cell = ws.cell(row=i, column=col[h])
        if cell.value in (None, ''):
            cell.value = v; cell.fill = SUG; cell.comment = Comment('Sugerido: ' + por, 'Cotizador'); n[h if h in n else 'filas'] += 0
            return True
    if len(sa.get(c, ())) == 1 and poner('operador_portuario', next(iter(sa[c])), 'Servicios adicionales (proveedor del puerto)'): n['puerto'] += 1
    if str(g('tipo_carga') or '').upper() in ('DRY', 'IMO') and str(g('clase_cnt') or '').upper() != 'RH' and poner('conexion', 'false', 'carga seca: sin conexión reefer'): n['conexion'] += 1
    if mov.get(c):
        m = sorted(mov[c])[0]
        ws.cell(row=i, column=ref, value=f"{m[0].strftime('%d/%m/%Y')} {m[2]} ({m[1]}) — el ingreso fue antes").font = Font(italic=True, color='5F6F66')
        n['referencia'] += 1
    for h in REQ:
        cell = ws.cell(row=i, column=col[h])
        if cell.value in (None, ''): cell.fill = FALTA
    if str(g('tipo_carga') or '').upper() == 'IMO' and g('clase_imo') in (None, ''): ws.cell(row=i, column=col['clase_imo']).fill = FALTA
wb.save(SAL); print(n)
