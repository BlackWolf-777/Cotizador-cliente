# Cotizador de Depósito Temporal

Soy ejecutivo de servicios logísticos en un depósito temporal del Callao. Este repositorio es la primera fase de un proyecto que empecé para resolver un problema de mi día a día: **cobrar bien, y a tiempo, cada contenedor que sale del depósito.**

**Demo (sin clave, datos ficticios):** https://cotizador-deposito-demo.vercel.app

![Cotizar](docs/img/02_cotizar.png)

> Todo lo que ves aquí usa **datos ficticios**: las empresas, los RUC, los contenedores, los BL, las facturas y las tarifas fueron reemplazados. Las datas de ejemplo conservan la forma y el volumen de la operación real, pero ninguna cifra corresponde a una empresa existente.

---

## Por qué lo hice

Para liquidar un contenedor tenía que cruzar a mano cuatro fuentes:

1. **La data del depósito:** tamaño y tipo del contenedor, puerto, fecha de ingreso, cliente y agencia de aduana.
2. **El tarifario del cliente:** cambia según el puerto, el tamaño, la carga peligrosa (IMO), el reefer y los días de almacenaje.
3. **El control de movilizaciones del depósito:** aforos, inspecciones SENASA, cuadrillas, montacargas, grúa.
4. **La facturación del puerto:** sobrecostos que el terminal le cobra al depósito y que, según el caso, hay que trasladar al cliente.

Con cinco contenedores al día, el problema no era el tiempo. El problema era que **algo se escapaba**: una cuadrilla que no se cobró, un sobrecosto del puerto que llegó tarde y se refacturó meses después, un almacenaje mal contado. Cada error terminaba en una nota de crédito o en un cobro fuera de tiempo, que es lo que más le cuesta a la relación con un cliente.

La carga suelta tenía su propio Excel, sin fórmulas, que se copiaba mes a mes desde que heredé la cuenta.

## Qué cambió

- **El cobro sale completo en la primera liquidación.** Los servicios del depósito y los sobrecostos del puerto que corresponde trasladar se suman en automático. Ya no dependen de que alguien los recuerde.
- **Se cobra dentro del ciclo de facturación,** no meses después. Dejamos de refacturar costos atrasados.
- **Aparecieron cobros que no se estaban haciendo.** Al recalcular 10 meses de liquidaciones de carga suelta, el sistema coincidió al centavo con lo facturado y, además, mostró días que no se cobraban en los meses de 31 días y salidas que no se liquidaron.
- **Todo queda registrado:** quién emitió, qué versión, con qué tarifa. Si algo cambia, se emite una nueva versión; nada se borra.

No publico montos porque son de la empresa. Lo que sí puedo decir es que el valor no estuvo en cotizar unos minutos más rápido, sino en **cobrar correctamente y a tiempo** lo que antes se perdía o llegaba tarde.

## Cómo se usa

1. Pego uno o varios BL o contenedores. Puede ser la tabla de un correo tal cual.
2. El sistema busca cada contenedor en la data del depósito. Si no lo encuentra, o le falta información, **no inventa nada**: dice qué falta.
3. Identifica el acuerdo comercial que corresponde. Puede ser con el cliente o con su agencia de aduana. En el segundo caso, el tarifario es el de la agencia pero se factura a cada cliente.
4. Arma la liquidación. Quito o agrego conceptos opcionales (transporte, pernocte, stand by…) y la emito.
5. Facturación recibe la liquidación como un paquete JSON, con rubros, tarifas e IGV.

Para la carga suelta hay un registro de stock por BL. Ahí quedan sus salidas (retiro, destrucción o adjudicación SUNAT), la liquidación mensual por periodos y la carga terrestre en depósito simple.

| | |
|---|---|
| ![Inicio](docs/img/01_inicio.png) | ![Carga suelta](docs/img/03_carga_suelta.png) |
| ![Liquidación mensual](docs/img/04_liquidacion_mensual.png) | ![Historial](docs/img/05_historial.png) |
| ![JSON para facturación](docs/img/06_liquidacion_json.png) | ![Tarifario](docs/img/07_tarifario.png) |

## Decisiones que tomé en el camino

- **Primero intenté con Power Apps.** No soportaba bien las condiciones encadenadas del tarifario: puerto, tamaño, IMO, reefer, días… Por eso pasé la lógica a SQL.
- **Las reglas son datos, no código.** Cada concepto del tarifario es una fila con su monto y su condición. Sumar un cliente nuevo es cargar su tarifario, no reprogramar nada. Así sumé el segundo acuerdo (una agencia de aduana con varios clientes) sin tocar el primero.
- **Si la agencia tiene acuerdo, prevalece sobre el del cliente.** Lo definí así porque la agencia es quien negocia el despacho. Si ninguno tiene acuerdo vigente, el sistema no cotiza.
- **Respeté reglas comerciales aunque no me parecieran lógicas.** El almacenaje de carga suelta reinicia sus periodos cada mes. No es lo más intuitivo, pero es lo pactado. El sistema replica el acuerdo, no lo reinterpreta.
- **La validación se hizo con datos reales.** Antes de confiar en un cálculo, lo comparé con liquidaciones que ya se habían facturado.
- **Lo construí en paralelo a la operación,** sin pedir accesos a los sistemas de la empresa. Así se podía probar sin riesgo y luego entregarlo a TI.

## Estado del proyecto

| Fase | Alcance | Responsable | Estado |
|---|---|---|---|
| **1. Diseño y piloto funcional** | Levantamiento del proceso, reglas de cobro, motor de cotización, carga de las tres datas, liquidaciones versionadas con JSON para facturación, carga suelta, acuerdos con cliente y con agencia. Piloto en paralelo a la operación. | Hernán Reyes | Completada |
| **2. Adaptación e integración corporativa** | Infraestructura de la empresa, conexión directa a los sistemas de origen, inicio de sesión corporativo con roles e integración con facturación. | Área de TI | Transferida a TI |

Este repositorio es la **Fase 1**: lo que entregué a TI como base para la Fase 2.

## Cómo lo construí

Yo puse el conocimiento del proceso:
- qué se cobra, cuándo, a quién y por qué;
- qué excepciones existen;
- cómo se valida que un cálculo está bien.

La programación la hice con **Claude (IA) como herramienta de desarrollo**. Yo definía cada regla y decidía cómo debía comportarse el sistema, y la IA escribía el código. Después revisaba el resultado contra casos reales y corregía. Fue un trabajo de ida y vuelta. La mayor parte del esfuerzo no estuvo en el código, sino en ordenar un tarifario que nadie había escrito completo y en encontrar los casos que rompían las reglas.

## Lo que aprendí

- Lo difícil no fue la tecnología: fue **ponerle reglas claras a un proceso que vivía en la cabeza de las personas** y en archivos heredados.
- Un sistema que dice *"no tengo información"* genera más confianza que uno que adivina.
- Validar contra la historia es la mejor forma de convencer: cuando los números cuadran al centavo con lo ya facturado, la conversación con el área de TI y con la jefatura cambia.
- Si lo empezara de nuevo, **mediría desde el primer día** (errores evitados, cobros recuperados, refacturaciones) para tener la línea base antes del cambio.

## Detalle técnico

```mermaid
flowchart LR
  subgraph Fuentes
    A[Data del depósito<br/>Excel] --> I
    B[Control de movilizaciones<br/>CSV] --> I
    C[Facturación del puerto<br/>CSV] --> I
  end
  I[Importación] --> DB[(PostgreSQL)]
  T[Tarifarios por acuerdo] --> DB
  DB --> M[Motor de cotización<br/>funciones SQL]
  M --> W[Web<br/>ajustes del ejecutivo]
  W --> E[Liquidación emitida<br/>versión + huella]
  E --> F[Facturación<br/>JSON]
```

- **Base de datos:** PostgreSQL. Toda la lógica de cobro está en funciones SQL, así que el mismo cálculo sirve para la web, para un reporte o para una integración, y TI la puede auditar en un solo lugar.
- **Aplicación:** Next.js + React, desplegada en Vercel. La base del piloto está en Neon.
- **Utilidades:** Python, para generar plantillas de Excel y para sugerir los datos que faltan en la data del depósito.

### La demo pública

La demo usa su propia base con datos ficticios y **se restaura sola todos los días**. Puedes probar todo: cotizar, emitir, facturar, registrar salidas.

Para que nadie pueda dañarla:
- **La carga de archivos está desactivada.**
- **Cada visitante tiene un límite** de tamaño de lo que envía y de operaciones por minuto.
- **La aplicación se conecta con un usuario que no puede modificar la estructura de la base** ni las tarifas.
- **Hay topes de registros por día.**
- **El navegador recibe cabeceras de seguridad** (por ejemplo, contra que la página se incruste en otro sitio).

### Ejecutarlo en tu equipo

Requisitos: Node.js 20 o superior y PostgreSQL 15 o superior.

```bash
git clone https://github.com/BlackWolf-777/Cotizador-cliente.git
cd Cotizador-cliente
cp .env.example .env.local        # completa DATABASE_URL
createdb cotizador
DATABASE_URL=postgresql://usuario:clave@localhost:5432/cotizador ./scripts/crear_bd_demo.sh
npm install
npm run dev                        # http://localhost:3000
```

En `datos_demo/` están las tres datas de ejemplo en su formato original, para probar **Cargar datos** en local.

```
app/            pantallas y API
components/     navegación y editor de líneas de liquidación
db/             esquema (con el motor de cotización) y datos de demostración
datos_demo/     las tres datas de entrada, de ejemplo
scripts/        plantillas de Excel y utilidades
```

---

**Hernán Reyes** · Ejecutivo de Servicios Logísticos Integrales · Callao, Perú
Si quieres conversar sobre el proyecto o sobre digitalización de procesos logísticos, escríbeme por LinkedIn.
