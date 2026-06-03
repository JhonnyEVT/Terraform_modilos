# Design — Candidate 3 Revisado: DynamoDB Section Store + S3 Archive + Valkey Cache

## 1. Resumen de decisiones

| Decisión | Valor |
|---|---|
| Target Architecture | DynamoDB como section store principal (no S3 Select) |
| Mecanismo de lectura | DynamoDB GetItem/BatchGetItem por sección |
| Cache | ElastiCache Valkey (obligatorio) |
| S3 | Archivo/backup de generaciones + fuente para backfill (no read path online) |
| Generaciones retenidas | 2 (activa + anterior) |
| Restricción Hydration | No puede durar más de 5 horas |
| Restricción API | Firma de APIs existentes se mantiene |
| QPS de diseño | 100 QPS |
| Cache hit ratio asumido | 30-40% (pesimista) |
| Secciones por request promedio | ~5 |
| S3 Select | NO DISPONIBLE (deprecated para nuevos clientes desde julio 2024) |

## 2. Por qué DynamoDB y no S3 Select

S3 Select fue cerrado a nuevos clientes por AWS en julio 2024. No podemos adoptarlo.

Sin S3 Select, leer secciones individuales de un objeto JSON en S3 requiere descargar el objeto completo — lo cual nos devuelve al mismo problema de over-fetch que queremos resolver.

DynamoDB resuelve esto nativamente: cada sección es un ítem independiente, recuperable en single-digit milliseconds sin leer las demás secciones.


## 3. Objetivo: Eliminar HBase del read path online

El diseño anterior relegaba la eliminación de HBase a una "Phase 4 futura". Este diseño replantea eso: **el objetivo es desacoplar completamente el read path online de HBase desde el inicio**.

HBase hoy se usa en el read path para 3 cosas:

| Uso en read path | Tablas HBase involucradas | ¿Se puede migrar a DynamoDB? |
|---|---|---|
| 1. PIN Resolution | pin-index-batch/realtime, near-neighbor-batch/realtime, stamped-identity-batch/realtime, identity-pin-map-realtime | **Sí** — son lookups por key, encajan perfectamente en DynamoDB |
| 2. XPM State (batch) | states-batch | **Sí** — es el core de este diseño (secciones en DynamoDB) |
| 3. XPM State (realtime) | states-realtime, event-store-realtime, states-vle | **Sí** — son lookups por PIN, migrables a DynamoDB o Valkey |
| 4. Extension Tables | inquiryFootprints, alerts, judicialInformation | **Sí** — son lookups por tipoDoc_numDoc |

**Conclusión:** No hay nada en el read path que requiera HBase técnicamente. Todo son lookups por key que DynamoDB maneja mejor, más rápido, y sin Kerberos.

HBase se mantiene **solo como destino de escritura del Hydrator** (BulkLoad) hasta que se decida si el Hydrator escribe directamente a DynamoDB o si se usa un job de conversión intermedio.

## 4. Arquitectura de alto nivel

```text
WRITE PATH (Hydration)
=======================
Pipeline EDF/Oxygen (sin cambios hasta StateCalc)
    |
    v
HydratorStateCalc (Spark/EMR) --> HBase states-batch (como hoy)
    |
    v
[NUEVO] Job de conversión (EMR Serverless)
    |
    ├── Lee output StateCalc (Avro+Snappy desde S3 staging)
    ├── Deserializa cada XPM
    ├── Escribe cada sección como ítem en DynamoDB
    ├── Escribe PIN resolution data en DynamoDB
    └── Escribe extension tables data en DynamoDB

Flujo Realtime (Kafka -> EMR -> DynamoDB realtime items) -- MIGRADO


READ PATH (Online Query)
=========================
Consumer -> API Gateway -> Data Provisioning Service (modificado)
    |
    ├── 1. Parse + Validate + Curate (sin cambio)
    |
    ├── 2. PIN Resolution (DynamoDB - MIGRADO desde HBase)
    |
    ├── 3. Extension Tables (DynamoDB - MIGRADO desde HBase, paralelo)
    |
    ├── 4. Lectura XPM por secciones:
    |      a) Valkey MGET por secciones pedidas
    |      b) Si HIT -> usar cache
    |      c) Si MISS -> DynamoDB BatchGetItem (solo secciones faltantes)
    |      d) Cachear en Valkey
    |
    ├── 5. Realtime merge (DynamoDB realtime items, si aplica)
    |
    ├── 6. generateView (filtros de producto, sin cambio lógico)
    |
    ├── 7. selectXPM (si múltiples candidatos)
    |
    └── 8. Response (firma API sin cambio)

RESULTADO: HBase NO participa en el read path online.
           Kerberos NO se necesita para consultas online.
```

## 5. Modelo de datos en DynamoDB

### 5.1 Tabla principal: section-store

Almacena las secciones del XPM como ítems individuales.

```text
Table: section-store

PK = PIN (string)          -- "7450577532313184495"
SK = GEN#SEC (string)      -- "gen_42#bestAccounts"

Attributes:
  payload        : map/string  -- contenido de la sección (JSON)
  sizeBytes      : number
  schemaVersion  : string
  classification : string      -- "PII" | "PCI" | "internal"
  updatedAt      : string      -- ISO 8601
  entity         : string      -- "person" | "companyxpm"
```

**Ejemplo de ítems para un PIN:**
```text
PK=7450577532313184495, SK=gen_42#names          -> {payload: [...], size: 2048, ...}
PK=7450577532313184495, SK=gen_42#bestAccounts   -> {payload: [...], size: 85000, ...}
PK=7450577532313184495, SK=gen_42#scores         -> {payload: [...], size: 1200, ...}
...
```

**Lectura de 5 secciones específicas:**
```text
BatchGetItem:
  Keys: [
    {PK: "7450577532313184495", SK: "gen_42#bestAccounts"},
    {PK: "7450577532313184495", SK: "gen_42#names"},
    {PK: "7450577532313184495", SK: "gen_42#scores"},
    {PK: "7450577532313184495", SK: "gen_42#bestIdentifications"},
    {PK: "7450577532313184495", SK: "gen_42#frequentBehaviour"}
  ]
```

Latencia: single-digit milliseconds. Solo lee las secciones pedidas. Over-fetch eliminado.


### 5.2 Manejo de secciones > 400 KB (heavy PINs)

DynamoDB tiene un límite de 400 KB por ítem. Para secciones que excedan este límite (posible en `bestAccounts` y `frequentBehaviour` de entidades legales):

**Estrategia: Partición automática por chunks**

```text
Si sección < 400 KB:
  1 ítem: PK=PIN, SK=gen_42#bestAccounts

Si sección > 400 KB:
  N ítems: PK=PIN, SK=gen_42#bestAccounts#chunk_0
           PK=PIN, SK=gen_42#bestAccounts#chunk_1
           PK=PIN, SK=gen_42#bestAccounts#chunk_2
  + 1 ítem metadata: PK=PIN, SK=gen_42#bestAccounts#_meta
                     {chunks: 3, totalSize: 850000}
```

El servicio detecta si hay chunks (por la presencia del ítem `#_meta`) y los ensambla en memoria. Esto es transparente para el consumidor.

**Alternativa para heavy sections: S3 como overflow**

```text
Si sección > 400 KB:
  DynamoDB ítem: PK=PIN, SK=gen_42#bestAccounts
                 {storageType: "s3", s3Key: "gen_42/overflow/PIN_bestAccounts.json.gz", size: 850000}
  
  El servicio detecta storageType=s3 y hace un S3 GET del objeto individual.
```

**Recomendación:** Usar chunks en DynamoDB (primera opción) porque mantiene la latencia en single-digit ms y evita el fan-out a S3. Solo usar S3 overflow si los chunks resultan operativamente complejos después de implementar.

### 5.3 Tabla: pin-resolution

Migra las tablas de PIN resolution de HBase a DynamoDB.

```text
Table: pin-resolution

-- PIN Index (reemplaza pin-index-batch/realtime)
PK = "IDX#" + identityId (hash)
SK = "BATCH" | "REALTIME"
Attributes:
  pins : string[]    -- lista de PINs asociados

-- Stamped Identity (reemplaza stamped-identity-batch/realtime)
PK = "STAMP#" + identityId
SK = "BATCH" | "REALTIME"
Attributes:
  pin       : string
  source    : string
  timestamp : string

-- Near Neighbor (reemplaza near-neighbor-batch/realtime)
PK = "NN#" + PIN
SK = "BATCH" | "REALTIME"
Attributes:
  taggedEvents : list   -- identidades vecinas
```

**Flujo de PIN resolution migrado:**
```text
1. Construir identityId desde atributos del inquiry
2. DynamoDB GetItem: PK="IDX#"+identityId, SK="BATCH"
   -> Si tiene PINs -> usar (fast path)
3. Si no -> GetItem: PK="IDX#"+identityId, SK="REALTIME"
4. Si no -> Query: PK="NN#"+PIN (near neighbors)
   -> Para cada vecino: GetItem en STAMP#identityId
   -> Obtener PIN
```

### 5.4 Tabla: extension-tables

Migra inquiryFootprints, alerts, judicialInformation de HBase a DynamoDB.

```text
Table: extension-data

PK = "DOC#" + tipoDoc + "_" + numDoc    -- "DOC#1_123456789"
SK = "EXT#" + tableName                  -- "EXT#inquiryFootprints"

Attributes:
  payload : map/string   -- contenido JSON de la extension table
  updatedAt : string
```

Lectura paralela (como hoy, pero contra DynamoDB):
```text
BatchGetItem:
  Keys: [
    {PK: "DOC#1_123456789", SK: "EXT#inquiryFootprints"},
    {PK: "DOC#1_123456789", SK: "EXT#alerts"},
    {PK: "DOC#1_123456789", SK: "EXT#judicialInformation"}
  ]
```

### 5.5 Tabla: generation-control

```text
Table: generation-control

PK = "TENANT#" + tenant
SK = "ENV#" + environment

Attributes:
  activeGenId    : string   -- "gen_42"
  previousGenId  : string   -- "gen_41"
  activatedAt    : string
  activatedBy    : string
```

### 5.6 Tabla: realtime-state

Migra states-realtime y event-store-realtime de HBase a DynamoDB.

```text
Table: realtime-state

PK = PIN
SK = "STATE" | "EVENTS" | "VLE"

Attributes:
  payload   : map/string
  updatedAt : string
  ttl       : number        -- epoch seconds para auto-expiración
```

TTL en DynamoDB reemplaza la purga semanal por Airflow: los ítems realtime expiran automáticamente (ej: TTL = 7 días).

## 6. Write Path — Job de conversión

### 6.1 Flujo principal (batch)

```text
Trigger: DAG Airflow (después de HydratorStateCalc + BulkLoad exitoso)

EMR Serverless Job (Spark/Scala o PySpark):
  Input: s3://pipeline-output/gen={genId}/statecalc/*.avro.snappy (~668.8 GB)
  
  Proceso por partición:
    1. Leer archivo Avro+Snappy
    2. Deserializar con schema
    3. Para cada XPM:
       a) Extraer cada sección como JSON
       b) Si sección < 400 KB: escribir 1 ítem en DynamoDB
       c) Si sección >= 400 KB: particionar en chunks, escribir N ítems
    4. Escribir PIN resolution data (identityId -> PIN mappings)
    5. Escribir extension tables data
  
  Output: ~72.3M PINs × ~30 secciones = ~2.17B ítems en DynamoDB
  
  Tiempo estimado: 2-3 horas con 200 vCPUs (DynamoDB on-demand escala)
  Costo por ejecución: ~$20-30 (compute) + ~$2,700 (DDB writes: 2.17B × $1.25/M)
```

### 6.2 Costo de escritura — análisis

El costo de escritura diaria a DynamoDB es significativo:
- 2.17B writes/día × $1.25/M = **~$2,700/día = ~$81,000/mes**

**Esto es PROHIBITIVO con escritura completa diaria.**

### 6.3 Optimización: escritura incremental (solo deltas)

La solución es **no reescribir toda la generación cada día**, sino solo los PINs que cambiaron:

```text
Estrategia Delta:
  1. Comparar generación nueva vs anterior (diff por PIN)
  2. Solo escribir ítems para PINs que cambiaron
  3. PINs sin cambio: mantener ítems existentes, actualizar solo el SK con nuevo genId
     (o usar un alias de generación que apunte a los mismos ítems)
```

**Estimación de deltas:**
- Si el pipeline procesa ~5-10% de PINs por día (dato a confirmar):
  - 72.3M × 10% = 7.23M PINs × 30 secciones = ~217M writes/día
  - 217M × $1.25/M = **~$271/día = ~$8,130/mes**

**Alternativa: modelo de generación por alias (sin reescritura)**

```text
Modelo sin reescritura completa:
  - SK NO incluye genId explícito
  - En su lugar: SK = sectionName (sin gen prefix)
  - Atributo "genId" indica a qué generación pertenece el dato
  - Al activar nueva generación: solo se actualizan los PINs que cambiaron
  - Los PINs que no cambiaron siguen sirviendo con el mismo ítem
  - generation-control indica cuál es la generación activa
  - Rollback: revertir los PINs que se actualizaron (log de cambios)
```

**Este modelo reduce el costo dramáticamente:**

```text
Table: section-store (modelo simplificado)

PK = PIN
SK = sectionName              -- "bestAccounts" (sin gen prefix)

Attributes:
  payload        : map/string
  genId          : string     -- "gen_42" (indica cuándo se escribió)
  sizeBytes      : number
  classification : string
  updatedAt      : string
```

- Escritura diaria: solo PINs que cambiaron × secciones que cambiaron
- Si ~10% de PINs cambian: ~7.23M PINs × ~5 secciones promedio que cambian = ~36M writes
- 36M × $1.25/M = **~$45/día = ~$1,350/mes** ← VIABLE

### 6.4 Modelo de generación elegido: Alias + Delta

```text
Diseño final:
  - DynamoDB almacena la versión MÁS RECIENTE de cada sección por PIN
  - Atributo genId indica en qué generación se escribió
  - Al procesar nueva generación: solo se escriben los PINs/secciones que cambiaron
  - Rollback: tabla de rollback-log con los valores anteriores de los PINs modificados
  - S3 mantiene el archivo completo por generación como backup/archive
```

**Ventajas:**
- Costo de escritura proporcional a los cambios, no al dataset completo
- Lectura siempre del ítem más reciente (no hay que filtrar por genId)
- Rollback posible vía rollback-log

**Trade-off:**
- Rollback es más complejo (hay que revertir ítems individuales vs. cambiar un puntero)
- Se pierde la capacidad de tener 2 generaciones "completas" coexistiendo en DynamoDB
- Mitigación: S3 mantiene generaciones completas como archive; si se necesita rollback total, se re-carga desde S3


## 7. Read Path — Flujo detallado

### 7.1 Secuencia completa (sin HBase)

```text
1. Consumer envía request HTTP (firma API sin cambio)

2. Data Provisioning Service:
   a) parseInquiry + validation + acceptance + curation (sin cambio)
   
   b) PIN Resolution (DynamoDB):
      - GetItem: PK="IDX#"+identityId, SK="BATCH"
      - Si no: GetItem SK="REALTIME"
      - Si no: Query PK="NN#"+PIN (near neighbors) + stamps
      Resultado: PIN = 7450577532313184495
   
   c) Extension Tables (DynamoDB, paralelo):
      - BatchGetItem: DOC#1_123456789 + EXT#inquiryFootprints/alerts/judicial
   
   d) Determinar secciones requeridas:
      - Parsear dataRequested -> lista de secciones
      - Aplicar autorización por sección
      - Resultado: sectionsToFetch = ["bestAccounts", "names", ...]
   
   e) Consultar Valkey:
      - MGET v1:pin:{PIN}:sec:{section} para cada sección
      - Separar: hits[] vs misses[]
   
   f) Si hay misses:
      - DynamoDB BatchGetItem:
        Keys = [{PK: PIN, SK: section} for section in misses]
      - Si alguna sección tiene chunks: leer chunks adicionales
      - Cachear en Valkey (SETEX con TTL)
   
   g) Realtime check (DynamoDB):
      - GetItem: PK=PIN, SK="STATE" en tabla realtime-state
      - Si hay datos -> merge con batch
   
   h) Ensamblar respuesta:
      - Combinar cache hits + DynamoDB reads + realtime merge
      - Inyectar extension tables
      - generateView (filtros)
      - selectXPM (si múltiples candidatos)
   
   i) Audit log (CloudWatch + CloudTrail)
   
   j) Response HTTP (firma sin cambio)
```

### 7.2 Latencia estimada por etapa

| Etapa | Latencia estimada | Notas |
|---|---:|---|
| Parse + validate + curate | ~3 ms | Sin cambio |
| PIN Resolution (DynamoDB) | ~5-15 ms | vs 30-200ms en HBase. Mejora 4-13x |
| Extension tables (DynamoDB, paralelo) | ~5-10 ms | vs ~10ms en HBase. Similar |
| Valkey MGET (5 secciones) | ~2-5 ms | |
| DynamoDB BatchGetItem (5 secciones miss) | ~5-15 ms | Single-digit ms por ítem |
| Chunk assembly (si aplica) | ~2-5 ms | Solo para secciones >400KB |
| Realtime check (DynamoDB) | ~3-5 ms | vs 1-5ms en HBase. Similar |
| generateView + filtros | ~69 ms | Sin cambio |
| selectXPM | ~0-123 ms | Solo si múltiples candidatos |
| **Total (miss, típico)** | **~95-250 ms** | |
| **Total (hit completo)** | **~75-140 ms** | |

**Comparación:**
- Estado actual (heavy PIN): ~2,176 ms
- Diseño anterior (S3 Select): ~210-580 ms
- **Este diseño (DynamoDB): ~95-250 ms** ← mejora de **9-23x** sobre el estado actual

### 7.3 Cache strategy

```text
Key:   v1:pin:{PIN}:sec:{sectionName}
Value: JSON string de la sección
TTL:   Configurable (default: 24h = hasta próxima generación)

Invalidación:
  - Cuando el job de conversión escribe un PIN actualizado:
    publicar evento a SNS/SQS -> Lambda invalida keys del PIN en Valkey
  - O: TTL natural (24h) absorbe la mayoría de casos
  - Realtime: merge sobreescribe datos batch (prioridad realtime > cache batch)
```

## 8. Integración con flujo Realtime

### 8.1 Migración del realtime a DynamoDB

En lugar de escribir a HBase realtime, el flujo realtime escribe directamente a DynamoDB:

```text
Evento nuevo (Kafka/MSK)
    |
    v
Procesamiento (EMR realtime o Lambda)
    |
    v
DynamoDB PutItem:
  Table: realtime-state
  PK = PIN
  SK = "STATE"
  payload = XPM actualizado con el evento
  ttl = now() + 7 días (auto-expiración)
    |
    v
[Opcional] Invalidar cache Valkey para este PIN
```

**Beneficios:**
- Elimina dependencia de HBase para realtime
- Elimina Kerberos del flujo realtime
- TTL automático reemplaza la purga semanal por Airflow
- Latencia de escritura: single-digit ms (vs 5-10 min actual a HBase)

### 8.2 Lectura con prioridad realtime

```text
if computeRealtimeStates:
  realtimeItem = DynamoDB GetItem(PK=PIN, SK="STATE", table=realtime-state)
  if realtimeItem exists and realtimeItem.updatedAt > batchItem.updatedAt:
    use realtimeItem (merge con batch si necesario)
  else:
    use batch sections from section-store
```

## 9. Generación y rollback

### 9.1 Modelo de generación (alias + delta)

```text
- DynamoDB section-store tiene la versión más reciente de cada sección
- Atributo genId indica en qué generación se escribió
- Job diario solo escribe PINs/secciones que cambiaron
- S3 mantiene archive completo por generación (backup)
```

### 9.2 Promotion de generación

```text
1. Job de conversión termina (solo deltas escritos a DynamoDB)
2. UpdateItem en generation-control: activeGenId = "gen_43"
3. Notificar Data Provisioning (endpoint o polling)
4. Data Provisioning actualiza referencia en memoria
5. Generación anterior: datos siguen en DynamoDB (no se borran)
```

### 9.3 Rollback

```text
Opción A (rápida, parcial):
  - Revertir ítems modificados usando rollback-log
  - UpdateItem generation-control: activeGenId = previousGenId
  - Tiempo: minutos (proporcional a PINs modificados)

Opción B (completa, desde S3):
  - Re-cargar generación anterior completa desde S3 archive
  - Sobreescribir DynamoDB con datos de la generación anterior
  - Tiempo: 1-2 horas (proporcional al dataset completo)
```

### 9.4 Cleanup

```text
- Rollback-log: TTL de 7 días (auto-expiración)
- S3 archive: lifecycle policy elimina generaciones > 4
- DynamoDB: no necesita cleanup explícito (siempre tiene la versión más reciente)
```

## 10. Autorización granular

(Sin cambio respecto al diseño anterior — Policy Store en DynamoDB + enforcement en servicio)

```text
Table: authorization-policies

PK = "CONSUMER#" + consumerId
SK = "SECTION#" + sectionName

Attributes:
  allowed         : boolean
  fieldExclusions : string[]
  updatedAt       : string
  updatedBy       : string
```

## 11. Componentes y clasificación

| Componente | Propósito | AWS Service | Estado |
|---|---|---|---|
| API Gateway | Ingress REST, auth binaria | API Gateway | unchanged |
| Data Provisioning Service | Orquesta read path | ECS Fargate | **modified** |
| DynamoDB section-store | Secciones XPM por PIN | DynamoDB | **new** |
| DynamoDB pin-resolution | Resolución documento -> PIN | DynamoDB | **new** |
| DynamoDB extension-data | Extension tables migradas | DynamoDB | **new** |
| DynamoDB realtime-state | Estado realtime con TTL | DynamoDB | **new** |
| DynamoDB generation-control | Control de generación activa | DynamoDB | **new** |
| DynamoDB authorization-policies | Políticas por consumidor/sección | DynamoDB | **new** |
| ElastiCache Valkey | Cache de secciones | ElastiCache Valkey | **new** |
| Job de conversión | Avro+Snappy -> DynamoDB ítems | EMR Serverless | **new** |
| S3 archive | Backup de generaciones completas | S3 | **new** (archive only) |
| HBase | Write target del Hydrator (BulkLoad) | HBase on EMR | **unchanged** (write only) |
| Airflow | Orquestación pipeline + job conversión | Airflow | **modified** |
| CloudWatch Logs | Audit logs | CloudWatch | **new** (granular) |
| SNS/SQS | Cache invalidation events | SNS + SQS | **new** |

**HBase queda FUERA del read path online.** Solo se mantiene como destino de escritura del Hydrator hasta que se decida si el Hydrator puede escribir directamente a DynamoDB (decisión futura).

## 12. Modelo de costos

### 12.1 Costo mensual sostenido

| Concepto | Costo estimado /mes | Notas |
|---|---:|---|
| DynamoDB storage (section-store: ~72.3M PINs × 30 secciones × ~10KB avg) | ~$5,400 | ~21.7 TB × $0.25/GB |
| DynamoDB reads (100 QPS × 5 secciones × 0.6 miss × 86400 × 30) | ~$200 | On-demand reads |
| DynamoDB writes (delta: ~36M writes/día × 30) | ~$1,350 | Solo PINs que cambian (~10%) |
| DynamoDB pin-resolution + extension + realtime (storage + reads) | ~$300 | Tablas más pequeñas |
| ElastiCache Valkey (r7g.large × 2 nodos) | ~$400 | HA 2 AZ |
| EMR Serverless (job conversión diario) | ~$600-900 | ~$20-30/ejecución × 30 |
| S3 archive (2 generaciones × ~700 GB) | ~$32 | Backup only |
| Data Provisioning Service (Fargate) | ~$870 | Existente |
| SNS/SQS (cache invalidation) | ~$10 | Bajo volumen |
| **Total** | **~$9,162-9,462** | |

### 12.2 Problema: DynamoDB storage cost

El costo dominante es **DynamoDB storage: ~$5,400/mes** para 21.7 TB.

Esto se debe a: 72.3M PINs × 30 secciones × ~10 KB promedio = ~21.7 TB.

**Opciones para reducir:**

1. **DynamoDB Standard-IA (Infrequent Access):** ~60% descuento en storage ($0.10/GB vs $0.25/GB)
   - Si la mayoría de PINs se consultan raramente (baja adopción actual), Standard-IA reduce storage a ~$2,170/mes
   - Trade-off: reads son ~25% más caros ($0.3125/M vs $0.25/M) pero con 100 QPS el impacto es mínimo

2. **Comprimir payloads:** Almacenar secciones como GZIP en DynamoDB (binary attribute)
   - Reduce storage ~60-70%: 21.7 TB → ~7-8 TB → ~$1,750-2,000/mes
   - Trade-off: CPU de descompresión en el servicio (~1-2ms por sección, despreciable)

3. **Combinar 1+2:** Standard-IA + GZIP → ~$700-800/mes de storage

**Con optimización (Standard-IA + GZIP):**

| Concepto | Costo optimizado /mes |
|---|---:|
| DynamoDB storage (Standard-IA + GZIP: ~7 TB) | ~$700 |
| DynamoDB reads | ~$250 |
| DynamoDB writes (delta) | ~$1,350 |
| DynamoDB otras tablas | ~$300 |
| ElastiCache Valkey | ~$400 |
| EMR Serverless | ~$750 |
| S3 archive | ~$32 |
| Data Provisioning | ~$870 |
| SNS/SQS | ~$10 |
| **Total optimizado** | **~$4,662** |

### 12.3 Comparación con baseline

| Escenario | Costo /mes | vs Baseline ($24,663) |
|---|---:|---:|
| Baseline actual (Hydrators + HBase + DP) | $24,663 | — |
| C3 DynamoDB (sin optimizar) | $9,462 + $22,793 (Hydrators) = $32,255 | +31% |
| C3 DynamoDB (optimizado IA+GZIP) | $4,662 + $22,793 (Hydrators) = $27,455 | +11% |
| C3 DynamoDB (optimizado, sin HBase) | $4,662 + $22,793 - $1,000 (HBase) = $26,455 | +7% |

**El incremento de costo (+7-11%) se justifica por:**
- Eliminación del cuello de botella de dehydrate (mejora latencia 9-23x)
- Eliminación de Kerberos del read path
- Eliminación del hotspot HBase
- Habilitación de autorización granular
- Lectura selectiva por sección (over-fetch eliminado)

## 13. Fases de implementación

### Phase 1: Infraestructura + Write path (4-5 semanas)
- Crear tablas DynamoDB (section-store, pin-resolution, extension-data, realtime-state, generation-control, authorization-policies)
- Crear cluster Valkey
- Crear CMKs por clasificación
- Desarrollar job de conversión EMR Serverless
- Ejecutar backfill inicial (generación activa + anterior)
- Validar datos en DynamoDB vs HBase (reconciliación)
- Todo en Terraform

### Phase 2: Read path migration (3-4 semanas)
- Modificar Data Provisioning: nuevo read path contra DynamoDB + Valkey
- Migrar PIN resolution a DynamoDB
- Migrar extension tables a DynamoDB
- Feature flag: nuevo path vs HBase path
- Shadow traffic: comparar resultados DynamoDB vs HBase
- Métricas de latencia por etapa

### Phase 3: Realtime + cutover (2-3 semanas)
- Migrar flujo realtime: Kafka -> DynamoDB (en lugar de HBase)
- Activar feature flag gradualmente (10% -> 50% -> 100%)
- Monitorear SLA compliance
- Desactivar lectura de HBase en Data Provisioning
- HBase queda solo como write target del Hydrator

### Phase 4: Autorización + observabilidad (2-3 semanas)
- Implementar Policy Store + enforcement
- Implementar audit logging granular
- Implementar restricción PII
- Integrar con CloudWatch + Athena

### Phase 5 (futuro): Eliminar HBase completamente
- Modificar Hydrator para escribir directamente a DynamoDB (sin HBase intermedio)
- O: mantener HBase como write buffer si el costo de modificar Hydrator es alto
- Decisión separada con su propio ADR

## 14. Riesgos y mitigaciones

| Riesgo | Severidad | Mitigación |
|---|---|---|
| Costo DynamoDB storage alto (~$5.4K/mes sin optimizar) | Alto | Standard-IA + GZIP reduce a ~$700/mes |
| Costo DynamoDB writes alto si se reescribe todo diario | Alto | Modelo delta (solo PINs que cambian) reduce de $81K a ~$1.35K/mes |
| Secciones > 400 KB requieren chunking | Medio | Implementar chunking transparente; monitorear % de secciones que lo necesitan |
| Job de conversión excede ventana disponible | Medio | EMR Serverless escala; modelo delta reduce volumen de escritura |
| Rollback más complejo que con generaciones explícitas | Medio | Rollback-log + S3 archive como fallback completo |
| Throttling DynamoDB durante backfill inicial | Medio | On-demand scaling; backfill gradual por particiones |
| Latencia de DynamoDB en cold start (table warming) | Bajo | On-demand mode maneja esto automáticamente |

## 15. Observabilidad

| Métrica | Herramienta | Alerta |
|---|---|---|
| Latencia end-to-end p99 | CloudWatch + Dynatrace | > 1000 ms por 5 min |
| Latencia DynamoDB reads p99 | CloudWatch | > 50 ms |
| Cache hit ratio | CloudWatch | < 25% sostenido |
| DynamoDB throttled requests | CloudWatch | > 0 sostenido |
| Job conversión duración | CloudWatch + Airflow | > 3 horas |
| Delta size (PINs modificados/día) | CloudWatch | > 20% del total (anomalía) |
| Costo diario DynamoDB | Cost Explorer | > $200/día |
| Secciones denegadas por autorización | CloudWatch Logs | Informativo |

## 16. Decisiones abiertas

| # | Decisión | Cuándo resolver |
|---|---|---|
| 1 | % real de PINs que cambian por generación (afecta costo de writes) | Phase 1, durante backfill |
| 2 | ¿Usar Standard-IA o Standard para DynamoDB? | Phase 1, basado en patrón de acceso real |
| 3 | ¿Comprimir payloads con GZIP en DynamoDB? | Phase 1, basado en trade-off CPU vs storage |
| 4 | ¿Chunking o S3 overflow para secciones > 400 KB? | Phase 1, basado en distribución real de tamaños |
| 5 | ¿Eliminar HBase del write path (Hydrator directo a DynamoDB)? | Phase 5, decisión separada |
| 6 | ¿Nuevos query keys (accountNumber, firstLastName) como GSIs en pin-resolution? | Phase 2 |
| 7 | ¿Restricción PII ≤2 campos: a qué nivel aplica? | Antes de Phase 4 |
