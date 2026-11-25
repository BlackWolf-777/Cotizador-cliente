"""Convierte un CSV exportado de Excel (latin-1 o utf-8) a JSONL: una fila = {encabezado: valor}.
Uso: python3 -I csv_a_jsonl.py archivo.csv salida.jsonl"""
import csv, json, sys
raw = open(sys.argv[1], 'rb').read()
try: txt = raw.decode('utf-8')
except UnicodeDecodeError: txt = raw.decode('latin-1')
rows = list(csv.reader(txt.splitlines()))
head = [h.strip() for h in rows[0]]
n = 0
with open(sys.argv[2], 'w') as out:
    for i, r in enumerate(rows[1:], start=2):
        d = {h: v.strip() for h, v in zip(head, r) if h and v.strip()}
        if not d: continue
        out.write(json.dumps({"fila": i, "datos": d}, ensure_ascii=False) + "\n"); n += 1
print(n, "filas")
