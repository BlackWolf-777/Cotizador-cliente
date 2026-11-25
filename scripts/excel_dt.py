"""Genera el Excel de la data del DT (mismo formato que acepta 'Cargar datos → Data del DT')."""
import json, sys, datetime as dt
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.utils import get_column_letter

datos = json.load(open(sys.argv[1])); salida = sys.argv[2]
VERDE = "009739"
COLS = [  # (columna, descripción, obligatoria, la usa el cotizador)
 ("tipo_servicio","IMPO o EXPO",True,True),("bk","BL (importación) o booking (exportación)",True,True),
 ("contenedor","Número de contenedor (4 letras + 7 dígitos)",True,True),("clase_cnt","ST, HC, RH u OT",True,True),
 ("tamano_cnt","20 o 40",True,True),("isotype","20ST, 40ST, 40HC, 20RH, 40RH, 20OT, 40OT",False,False),
 ("condicion_cnt","FCL",True,False),("tipo_carga","DRY, REFRIGERADA o IMO",True,True),
 ("clase_imo","Solo si es IMO: Clase 1, 2, 3, 4, 5.1, 5.2, 6.1, 6.2, 7, 8 o 9",False,True),
 ("fecha_ingreso_balanza","Fecha de ingreso al DT",True,True),("hora_ingreso_balanza","Hora de ingreso (HH:MM)",False,False),
 ("cliente","Razón social del cliente",True,True),("ruc_cliente","RUC del cliente (identifica el tarifario)",True,True),
 ("operador_portuario","APM o DPW",True,True),("conexion","Reefer conectado: true / false",True,True),
 ("temperatura","Solo reefer conectado",False,False),("linea_maritima","Línea naviera",False,True),
 ("agencia_aduana","Agencia de aduana",False,True),("mercaderia","Descripción de la mercadería",False,False),
 ("orden_servicio","",False,False),("cod_linea","",False,False),("codigo_nave","",False,False),("nave","",False,False),
 ("numero_viaje","",False,False),("cod_agen_maritimo","",False,False),("agente_maritimo","",False,False),
 ("cod_agencia","",False,False),("ruc_agencia_aduana","",False,False),("codigo_puerto_destino","",False,False),
 ("puerto_destino","",False,False),("codigo_puerto_origen","",False,False),("puerto_origen","",False,False),
 ("sede","",False,False),("lugar_llenado","",False,False),("zona","",False,False),("balancero","",False,False),
 ("guia_ingreso","",False,False),("nro_mercaderia","",False,False),
]
wb = Workbook(); ws = wb.active; ws.title = "DT"
borde = Border(bottom=Side(style="thin", color="DFE8E2"))
for j, (c, d, oblig, usa) in enumerate(COLS, 1):
    cell = ws.cell(row=1, column=j, value=c)
    cell.font = Font(bold=True, color="FFFFFF" if oblig else "1D2B23")
    cell.fill = PatternFill("solid", fgColor=VERDE if oblig else ("CDEBD6" if usa else "EEF2EF"))
    cell.alignment = Alignment(horizontal="center", vertical="center")
    ws.column_dimensions[get_column_letter(j)].width = max(12, min(30, len(c) + 4))
for i, r in enumerate(datos, 2):
    for j, (c, *_ ) in enumerate(COLS, 1):
        v = r.get(c)
        if c == "fecha_ingreso_balanza" and v: v = dt.date.fromisoformat(v)
        if c == "conexion": v = "true" if v else "false"
        if c == "hora_ingreso_balanza" and v: v = v[:5]
        cell = ws.cell(row=i, column=j, value=v)
        cell.border = borde
        if c == "fecha_ingreso_balanza": cell.number_format = "DD/MM/YYYY"
        if c in ("ruc_cliente", "ruc_agencia_aduana", "guia_ingreso"): cell.number_format = "0"
ws.freeze_panes = "D2"; ws.auto_filter.ref = f"A1:{get_column_letter(len(COLS))}{max(2, len(datos)+1)}"
ws.row_dimensions[1].height = 22
listas = {"tipo_servicio": "IMPO,EXPO", "clase_cnt": "ST,HC,RH,OT", "tamano_cnt": "20,40",
          "isotype": "20ST,40ST,40HC,20RH,40RH,20OT,40OT", "condicion_cnt": "FCL", "tipo_carga": "DRY,REFRIGERADA,IMO",
          "clase_imo": "Clase 1,Clase 2,Clase 3,Clase 4,Clase 5.1,Clase 5.2,Clase 6.1,Clase 6.2,Clase 7,Clase 8,Clase 9",
          "operador_portuario": "APM,DPW", "conexion": "true,false"}
for j, (c, *_ ) in enumerate(COLS, 1):
    if c in listas:
        dv = DataValidation(type="list", formula1=f'"{listas[c]}"', allow_blank=True, showErrorMessage=True,
                            errorTitle="Valor no válido", error=f"Valores permitidos: {listas[c]}")
        ws.add_data_validation(dv); col = get_column_letter(j); dv.add(f"{col}2:{col}2000")

ins = wb.create_sheet("Instrucciones")
ins["A1"] = "Data del DT — cómo llenarla"; ins["A1"].font = Font(bold=True, size=14, color=VERDE)
textos = [
 "Esta es la primera consulta del cotizador: si un BL o contenedor no está aquí, no se cotiza.",
 "Una fila = un contenedor. Si un BL tiene 3 contenedores, son 3 filas con el mismo valor en 'bk'.",
 "Columnas en verde oscuro: obligatorias. Verde claro: las usa el cotizador o se muestran en la liquidación. Gris: informativas.",
 "No cambies los nombres de las columnas. Puedes dejar vacías las informativas.",
 "Para cargar: Cotizador → Cargar datos → 'Data del DT' → elegir este archivo. Si el contenedor ya existe (mismo tipo_servicio + bk + contenedor), se actualiza.",
 "Las filas con 'SIMULADO' en mercadería y los TSTU... son datos de prueba: reemplázalos por los reales o bórralos.",
]
for k, t in enumerate(textos, 3): ins.cell(row=k, column=1, value="• " + t)
fila = len(textos) + 5
for j, h in enumerate(["Columna", "Qué va", "Obligatoria", "La usa el cotizador"], 1):
    c = ins.cell(row=fila, column=j, value=h); c.font = Font(bold=True, color="FFFFFF"); c.fill = PatternFill("solid", fgColor=VERDE)
for k, (c, d, o, u) in enumerate(COLS, fila + 1):
    ins.cell(row=k, column=1, value=c); ins.cell(row=k, column=2, value=d)
    ins.cell(row=k, column=3, value="Sí" if o else ""); ins.cell(row=k, column=4, value="Sí" if u else "")
ins.column_dimensions["A"].width = 26; ins.column_dimensions["B"].width = 70
ins.column_dimensions["C"].width = 12; ins.column_dimensions["D"].width = 20
wb.save(salida); print("ok", len(datos), "filas")
