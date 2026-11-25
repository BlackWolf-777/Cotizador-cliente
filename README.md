# Cotizador de Depósito Temporal

**Liquidación automática de servicios de importación (contenedores y carga suelta) para un depósito temporal portuario.**
De un proceso manual en hojas de cálculo a un sistema web en el que se pega un BL o un contenedor y se obtiene la liquidación lista para facturar.

> Proyecto real, publicado con **datos ficticios**: empresas, RUC, contenedores, BL, facturas y tarifas fueron reemplazados.
> Las datas de ejemplo conservan la forma y el volumen de una operación real, pero ninguna cifra corresponde a una empresa existente.

![Cotizar](docs/img/02_cotizar.png)

---

## El problema

En un depósito temporal del Callao, cada contenedor que se retira genera una liquidación que combina **cuatro fuentes**:

| Fuente | Qué aporta |
|---|---|
| **Data del depósito (DT)** | Características del contenedor: tamaño, tipo (seco, reefer, IMO), puerto de descarga, fecha de ingreso, cliente y agencia de aduana |
| **Tarifario comercial** | Las tarifas pactadas, que cambian según puerto, tamaño, tipo de carga, clase IMO y días de almacenaje |
| **Control de movilizaciones** | Los servicios operativos del DT: aforos, inspecciones SENASA, cuadrillas, montacargas, grúa |
| **Facturación del puerto** | Sobrecostos que el terminal portuario cobra y que se trasladan (o no) al cliente |

Antes se cruzaba todo a mano, contenedor por contenedor. Eso producía errores de cobro, notas de crédito y horas de trabajo repetitivo. La carga suelta se controlaba en un Excel sin fórmulas, copiado mes a mes.

## La solución

Un cotizador web en el que **toda la lógica de cobro vive en la base de datos** (funciones PostgreSQL) y la interfaz solo muestra y permite ajustar.

1. Se pegan uno o varios **BL o contenedores** (también la tabla de un correo tal cual).
2. El sistema busca cada contenedor en la **data del DT**. Si no está o le falta información, **no cotiza** y dice exactamente qué falta.
3. Determina el **acuerdo comercial** que aplica: el de la agencia de aduana, si tiene uno vigente; si no, el del cliente.
4. Aplica las **reglas del tarifario**, suma los servicios del DT y los sobrecostos del puerto que corresponde refacturar.
5. El ejecutivo quita o agrega conceptos opcionales y **emite**. La liquidación queda versionada, con una huella SHA-256, y pasa a la **bandeja de facturación** como un paquete **JSON**.

### Funcionalidades

- **Cotización por BL o contenedor**, en lote, con validación del dígito de control **ISO 6346**.
- **Acuerdos comerciales con el cliente o con la agencia de aduana.** En el segundo caso el tarifario es el de la agencia, pero se factura a cada consignatario.
- **Reglas como datos, no como `IF` anidados.** Cada concepto tiene un *disparador* (`SIEMPRE`, `DPW`, `IMO`, `CONEXION`, `CUADRILLA`, `MONTACARGA`, `SINI`, `ALMACENAJE`, `MANUAL`…). Agregar un cliente nuevo es cargar su tarifario, no programar.
- **Almacenaje** automático pasados los días libres; reefer por días de conexión; segregación IMO por grupo de clase.
- **Facturación del puerto:** distingue lo que asume el depósito de lo que se traslada al cliente, y agrega el gasto administrativo de recupero.
- **Carga suelta:**
  - stock por BL, con salidas registradas (retiro, destrucción o adjudicación SUNAT) y una bitácora inmutable;
  - liquidación mensual por periodos (1–5, 6–10, 11–20, 21+), con tarifa por tonelada desde 1 TN y días parciales en el mes de ingreso o salida;
  - carga terrestre en depósito simple: ingreso más los recursos usados.
- **Ciclo de vida:** emitida → facturada / reemplazada / anulada, con historial de versiones.
- **Carga de datos desde Excel/CSV.** Lo incompleto queda como *pendiente*, con la lista de campos que faltan.

| | |
|---|---|
| ![Inicio](docs/img/01_inicio.png) | ![Carga suelta](docs/img/03_carga_suelta.png) |
| ![Liquidación mensual](docs/img/04_liquidacion_mensual.png) | ![Historial](docs/img/05_historial.png) |
| ![JSON para facturación](docs/img/06_liquidacion_json.png) | ![Tarifario](docs/img/07_tarifario.png) |

## Arquitectura

```mermaid
flowchart LR
  subgraph Fuentes
    A[Data del DT<br/>Excel] --> I
    B[Control de movilizaciones<br/>CSV] --> I
    C[Facturación del puerto<br/>CSV] --> I
  end
  I[Importación por bloques<br/>ops.procesar_*] --> DB[(PostgreSQL)]
  T[Tarifarios por acuerdo<br/>tarifas.regla] --> DB
  DB --> M[Motor de cotización<br/>liq.cotizar / liq.cotizar_json]
  M --> W[Web Next.js<br/>ajustes del ejecutivo]
  W --> E[liq.emitir<br/>versión + hash SHA-256]
  E --> F[Bandeja de facturación<br/>JSON]
```

| Capa | Tecnología |
|---|---|
| Base de datos | PostgreSQL. Esquemas `core`, `dt`, `ops`, `tarifas`, `liq` y `cs`, con la lógica en funciones PL/pgSQL |
| Aplicación | Next.js 15 (App Router) + React 19, con el driver `pg` y sin ORM |
| Despliegue del piloto | Vercel + Neon (PostgreSQL serverless) |
| Utilidades | Python (openpyxl) para plantillas de Excel y para sugerir datos faltantes |

### Decisiones de diseño

- **La lógica en SQL, no en la web.** El mismo cálculo sirve para la interfaz, para una integración futura con el sistema de facturación o para un reporte. TI puede auditarlo en un solo lugar.
- **Reglas como datos.** Un tarifario es un conjunto de filas con monto, condición y disparador. Cambiar una tarifa o sumar un cliente no requiere desplegar código.
- **Nada se borra.** Las liquidaciones se reemplazan con una nueva versión y las salidas de carga suelta quedan en una bitácora.
- **"No hay información" es un resultado válido.** Si la data del DT está incompleta, el sistema lo dice y no adivina.
- **Validación contra la historia.** La liquidación mensual de carga suelta se recalculó sobre 10 meses de liquidaciones manuales: coincidió al centavo y además reveló días no cobrados en meses de 31 días.

## Demo en línea

La demo pública usa una base propia con los mismos datos ficticios. Se reinicia todos los días (cron de Vercel → `/api/demo/reiniciar`), así que se puede probar libremente: cotizar, emitir, facturar o registrar salidas.

## Ejecutar en local

Requisitos: Node.js 20+ y PostgreSQL 15+.

```bash
git clone https://github.com/BlackWolf-777/Cotizador-cliente.git
cd Cotizador-cliente
cp .env.example .env.local        # y completa DATABASE_URL
createdb cotizador
DATABASE_URL=postgresql://usuario:clave@localhost:5432/cotizador ./scripts/crear_bd_demo.sh
npm install
npm run dev                        # http://localhost:3000
```

La base de demo trae 2 acuerdos comerciales (un cliente directo y una agencia de aduana), unos 300 contenedores, movilizaciones, facturación del puerto, stock de carga suelta y algunas liquidaciones ya emitidas. Las fechas son relativas al día en que se crea la base.

En `datos_demo/` están las tres datas en su formato original (`DATA_DT.xlsx`, `control_movilizaciones.csv` y `servicios_adicionales.csv`), para probar la pantalla **Cargar datos**.

## Estructura

```
app/            páginas y API (Next.js App Router)
components/     navegación y editor de líneas de liquidación
lib/            conexión a la base y formato
db/schema.sql   esquema completo: tablas, funciones del motor y vistas
db/seed_*.sql   tarifarios ficticios, datas de demo y casos de ejemplo
datos_demo/     las tres datas de entrada, de ejemplo
scripts/        plantillas de Excel y utilidades de carga
```

## Autor

**Hernán Reyes** · Ejecutivo de Servicios Logísticos Integrales.
Definí el proceso, las reglas de negocio y los criterios de validación, y lideré el piloto. El desarrollo se hizo con asistencia de IA (Claude).
