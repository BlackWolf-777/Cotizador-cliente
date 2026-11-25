#!/usr/bin/env bash
# Crea la base de datos de la demo: esquema + tarifarios ficticios + datas anonimizadas + casos de ejemplo.
# Uso: DATABASE_URL=postgresql://usuario:clave@host:5432/base ./scripts/crear_bd_demo.sh
set -euo pipefail
: "${DATABASE_URL:?Define DATABASE_URL}"
cd "$(dirname "$0")/.."
for f in db/schema.sql db/seed_tarifas_demo.sql db/seed_datos_demo.sql db/seed_casos_demo.sql; do
  echo "→ $f"; psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$f" > /dev/null
done
echo "Listo. Ejecuta: npm install && npm run dev"
