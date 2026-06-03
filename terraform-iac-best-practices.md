---
inclusion: fileMatch
fileMatchPattern: "*.tf"
---

# Terraform IaC Best Practices

Steering file que codifica las prácticas que el agente debe aplicar al escribir, revisar o modificar archivos Terraform en este proyecto. Auto-cargado al editar `*.tf`.

Este steering consolida guidance oficial de [HashiCorp Developer](https://developer.hashicorp.com/terraform), [AWS Prescriptive Guidance — Terraform AWS Provider Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/introduction.html) y prácticas comunes de la comunidad (tflint, tfsec/trivy, Checkov, pre-commit). Contenido reformulado para cumplir con licencias.

---

## 1. Principios rectores

1. **Terraform es la única forma de cambiar infraestructura.** Cambios en consola están prohibidos salvo emergencias documentadas; cualquier drift se reconcilia importando o destruyendo.
2. **El plan es la verdad.** Ningún `apply` ocurre sin que un humano (o un policy check automatizado) revise el plan.
3. **Versiones pinneadas siempre.** Terraform core, providers y módulos: rangos cerrados. Nunca `latest`.
4. **Estado remoto, cifrado, con locking.** Nunca estado local en producción.
5. **Secrets jamás en HCL ni en `.tfvars` versionados.** Vienen de AWS Secrets Manager o SSM Parameter Store via `data` sources.
6. **Least privilege en IAM por defecto.** Wildcards (`*`) requieren justificación escrita en comentario inline.
7. **Tags consistentes** en todos los recursos taggable, vía `default_tags` del provider más `locals.common_tags`.
8. **Cifrado en reposo y en tránsito** activado en todo recurso que lo soporte. KMS CMK donde aplique compliance (PCI, datos sensibles).
9. **Validación shift-left:** `fmt`, `validate`, `tflint`, `trivy` (o `tfsec`/`checkov`) en pre-commit y en CI.
10. **Documentación junto al código:** `README.md` por módulo, generado o asistido por `terraform-docs`.

---

## 2. Versionado y `versions.tf`

Cada módulo o root tiene un `versions.tf` con constraints explícitos:

```hcl
terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
```

Reglas:

- Terraform core: rango con upper bound (evitar romper en major).
- Providers: pessimistic constraint `~>` al minor (`~> 5.70` permite 5.70.x, 5.71.x, ... 5.99.x, no 6.x).
- Antes de actualizar un provider, leer el changelog y correr `terraform plan` contra el último estado. Si hay cambios, abrir PR de upgrade aislado.
- El `provider_doc_id` y la versión exacta se obtienen vía la Terraform power (`get_latest_provider_version`) cuando corresponda.

---

## 3. Estructura de archivos y módulos

### 3.1 Estructura estándar de un módulo

```
module-name/
├── README.md           # Docs (generadas con terraform-docs)
├── versions.tf         # required_version + required_providers
├── providers.tf        # Configuración del provider (root only; módulos no la fijan)
├── variables.tf        # Inputs, con description, type y validation
├── main.tf             # Recursos principales
├── outputs.tf          # Outputs, con description y sensitive cuando aplique
├── locals.tf           # Cuando hay >5 locals; si no, en main.tf
├── data.tf             # Data sources (cuando hay >3; si no, junto al recurso que los usa)
├── iam.tf              # Roles, políticas, policy documents (cuando aplique)
├── <recurso-grande>.tf # Cuando main.tf supera 15 recursos, dividir por dominio
└── examples/           # Ejemplos consumibles, cada uno es un root module
    ├── basic/
    └── complete/
```

Reglas:

- `main.tf` no excede ~15 recursos. Cuando lo hace, dividir por dominio funcional: `network.tf`, `database.tf`, `monitoring.tf`, `opensearch.tf`, etc.
- Outputs **siempre** en `outputs.tf`, nunca embebidos junto a recursos en otros archivos.
- `providers.tf` solo en el **root module**; los child modules heredan provider del caller (con alias si aplica).
- `examples/` es obligatorio en módulos publicados al registry (privado o público).
- `tests/` con `*.tftest.hcl` para módulos críticos (Terraform 1.6+ native test framework).

### 3.2 Estructura de repositorio

```
repo-root/
├── modules/             # Reusable modules (private registry candidates)
│   ├── vpc/
│   ├── aurora-cluster/
│   └── lookup-index-ddb/
├── envs/                # Root configurations por ambiente
│   ├── dev/
│   ├── staging/
│   └── prod/
├── policies/            # Sentinel / OPA policies (si aplica)
├── .pre-commit-config.yaml
├── .tflint.hcl
└── README.md
```

Decisión monorepo vs polyrepo:

- **Monorepo** cuando infraestructura y aplicación evolucionan juntas (serverless, microservicios con su propia infra).
- **Polyrepo** cuando la infraestructura core la administra un equipo separado y el cadencias de release difieren.

### 3.3 Composición de módulos

- Mantener el árbol de módulos **plano**. Composición en el root, no anidamiento profundo.
- Un módulo debería tener un propósito claro y un blast radius acotado (regla informal: si su `terraform plan` toca >50 recursos, está demasiado grande).
- Wrappear módulos públicos cuando hace falta agregar políticas organizacionales — no copiar y pegar.

---

## 4. Naming conventions

```hcl
# snake_case en TODO: recursos, variables, outputs, locals, módulos
resource "aws_security_group" "allow_https"        {}   # bien
resource "aws_security_group" "allowHTTPS"         {}   # mal
resource "aws_security_group" "allow-https"        {}   # mal (kebab-case en HCL)

variable "instance_type"        {}
variable "enable_monitoring"    {}
variable "database_password"    { sensitive = true }

locals {
  name_prefix = "${var.project}-${var.environment}"
}
```

Reglas:

- Identificadores de recursos en HCL: `snake_case`. Sin redundancia con el tipo: `aws_s3_bucket.logs`, no `aws_s3_bucket.logs_bucket`.
- Nombres de recursos AWS visibles (Name tag, bucket names): `kebab-case` con prefijo de proyecto y ambiente: `dataprov-prod-aurora-cluster`.
- Variables booleanas: prefijo `enable_`, `is_`, `has_` (`enable_dns_hostnames`, `is_public`).
- Outputs: nombre del atributo expuesto (`vpc_id`, `database_endpoint`), no `output_vpc_id`.

---

## 5. Variables y outputs

### 5.1 Variables

Toda variable tiene `description` y `type`. Variables sensibles tienen `sensitive = true`. Variables con dominio cerrado tienen `validation`.

```hcl
variable "environment" {
  description = "Deployment environment. Used in tags and naming."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "instance_class" {
  description = "RDS instance class. Must be a valid db.* class."
  type        = string

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "instance_class must start with 'db.'."
  }
}

variable "database_password" {
  description = "Master password for the database. Sourced from Secrets Manager in production."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Additional tags merged on top of common_tags."
  type        = map(string)
  default     = {}
}
```

Reglas:

- Defaults solo cuando hay un valor sensato genérico. Si el valor depende del ambiente, **no** poner default.
- Tipos complejos (`object({...})`, `list(object({...}))`) preferidos sobre `any` o `map(any)`.
- `nullable = false` cuando la variable es obligatoria.

### 5.2 Outputs

```hcl
output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint. Use this for write traffic."
  value       = aws_rds_cluster.main.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint. Use this for read traffic."
  value       = aws_rds_cluster.main.reader_endpoint
}

output "master_password" {
  description = "Master password (sensitive)."
  value       = aws_rds_cluster.main.master_password
  sensitive   = true
}
```

- Todo output con `description`.
- Outputs que exponen secretos o datos sensibles: `sensitive = true`.
- No exportar outputs solo "por si acaso". Si no se consume, se borra.

---

## 6. Estado remoto

### 6.1 Backend recomendado: S3 con state locking nativo (Terraform 1.10+)

A partir de Terraform 1.10 el backend `s3` soporta locking nativo (sin DynamoDB). Para versiones anteriores o pipelines que aún lo requieren, mantener DynamoDB con `LockID` como PK.

```hcl
# Terraform >= 1.10 (recomendado)
terraform {
  backend "s3" {
    bucket       = "tfstate-dataprov-prod-us-east-1"
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:111122223333:alias/tfstate"
    use_lockfile = true              # native S3 locking, replaces DynamoDB
  }
}
```

```hcl
# Terraform < 1.10 (DynamoDB locking, todavía soportado)
terraform {
  backend "s3" {
    bucket         = "tfstate-dataprov-prod-us-east-1"
    key            = "envs/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:us-east-1:111122223333:alias/tfstate"
    dynamodb_table = "tfstate-locks"
  }
}
```

Reglas del bucket de estado:

- **Versionado activado** (rollback a estado previo en caso de corrupción).
- **Cifrado SSE-KMS** con CMK gestionado por el equipo de plataforma.
- **Acceso público bloqueado** (Public Access Block en los 4 settings).
- **Bucket policy** restrictiva: solo los roles de CI/CD y de operadores autorizados.
- **MFA Delete** considerado para producción.
- **Replicación cross-region** del bucket de state cuando hay requerimiento de DR.
- **Una key por root module** — no compartir state entre roots.

### 6.2 Workspaces vs directorios separados

- Para separar **ambientes** (dev/staging/prod): usar **directorios separados** (`envs/dev`, `envs/prod`) con sus propios backends. Workspaces no son adecuados para multi-ambiente productivo.
- Workspaces son útiles para iterar sobre variantes efímeras del mismo root module (PR previews, branch-per-feature).

### 6.3 HCP Terraform / Terraform Cloud

Cuando el equipo usa HCP Terraform, el backend `remote` o `cloud` reemplaza a `s3`. La gobernanza, runs y variable sets se gestionan vía workspaces de HCP. Las prácticas de pinning, naming y validación siguen aplicando.

---

## 7. Providers

### 7.1 Provider AWS — configuración base

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }

  # Para roles cross-account / cross-region usar provider alias:
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  assume_role {
    role_arn     = var.dr_account_role_arn
    session_name = "terraform-${var.environment}"
  }

  default_tags {
    tags = local.common_tags
  }
}
```

Reglas:

- **`default_tags` siempre activado** en el provider AWS. Reduce la superficie de tags olvidados.
- **`assume_role`** en lugar de credenciales estáticas. En CI/CD usar OIDC federation (GitHub Actions, GitLab CI) hacia un IAM role.
- Un provider por región/cuenta vía `alias`. No mezclar múltiples cuentas en un mismo módulo sin alias explícito.
- No fijar versión en el bloque `provider`; las versiones van en `required_providers` (`versions.tf`).

### 7.2 Tags estándar

```hcl
locals {
  common_tags = {
    Project       = var.project
    Environment   = var.environment
    Owner         = var.team_owner
    CostCenter    = var.cost_center
    ManagedBy     = "terraform"
    Repository    = var.git_repository
    DataClass     = var.data_classification    # public | internal | restricted | pci
  }
}
```

- Estos tags se aplican vía `default_tags`. El recurso individual solo agrega tags específicos: `Name`, `Component`, etc.
- Cumplimiento de tags vía AWS Organizations Tag Policies cuando aplica. Validación shift-left con `tflint` o policy-as-code.

---

## 8. Security

### 8.1 Reglas firmes

| Regla | Implementación |
|---|---|
| Sin credenciales en código | Provider via `assume_role` + OIDC; secretos via `data` sources |
| Cifrado at-rest siempre | `kms_key_id` en S3, RDS, EBS, DynamoDB, etc. |
| Cifrado in-transit siempre | TLS en endpoints, `enforce_in_transit_encryption = true` donde aplique |
| Least-privilege IAM | `aws_iam_policy_document` con resources específicos, sin `"*"` salvo justificación inline |
| Sin S3 público | `aws_s3_bucket_public_access_block` con los 4 settings en `true` |
| Security groups acotados | Sin `0.0.0.0/0` en ingress salvo HTTPS público explícitamente justificado |
| Logs sin secretos | CloudTrail data events para S3/Lambda; CloudWatch logs sin payloads sensibles |
| MFA en root | Fuera de Terraform (configuración de cuenta) pero verificado por audit |

### 8.2 Secrets

```hcl
# Lectura de secret existente (no creación con valor en HCL)
data "aws_secretsmanager_secret" "db" {
  name = "prod/dataprov/aurora/master"
}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = data.aws_secretsmanager_secret.db.id
}

resource "aws_rds_cluster" "main" {
  master_username    = "admin"
  master_password    = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)["password"]
  # ...
}
```

- El secreto se **crea fuera de Terraform** (rotación automática vía Lambda gestionada por AWS).
- Si Terraform debe crearlo, usar `aws_secretsmanager_secret` + `aws_secretsmanager_secret_version` con `lifecycle.ignore_changes = [secret_string]` y poblarlo después.
- Nunca commitear `*.auto.tfvars` ni `terraform.tfvars` con secretos. Agregarlos a `.gitignore` y proveer un `.tfvars.example` plantilla.

### 8.3 IAM — patrón estándar

```hcl
data "aws_iam_policy_document" "lambda_logs" {
  statement {
    sid       = "AllowCloudWatchLogs"
    effect    = "Allow"
    actions   = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.function_name}:*",
    ]
  }
}

resource "aws_iam_policy" "lambda_logs" {
  name   = "${local.name_prefix}-lambda-logs"
  policy = data.aws_iam_policy_document.lambda_logs.json
}
```

- **`aws_iam_policy_document`** preferido sobre policy JSON inline o heredoc.
- Cada `statement` con `sid` descriptivo.
- Resources expandidos con ARNs construidos a partir de `data.aws_caller_identity.current.account_id` y `data.aws_region.current.name`. Nunca hardcoded.
- `Condition` blocks para reforzar (e.g. `aws:SourceArn`, `aws:ResourceTag/Environment`).

---

## 9. Patrones HCL

### 9.1 `count` vs `for_each`

- **`count`** solo para "encender/apagar" un recurso (`count = var.enabled ? 1 : 0`).
- **`for_each`** para colecciones. Siempre con `set` o `map`, nunca con `list` (cambios en el medio de la lista provocan recreación).

```hcl
# Bien
resource "aws_subnet" "private" {
  for_each = {
    for idx, az in var.availability_zones : az => idx
  }

  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value)
  vpc_id            = aws_vpc.main.id
}

# Mal — usa list, sensible al orden
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  availability_zone = var.availability_zones[count.index]
  # ...
}
```

### 9.2 `dynamic` blocks

Para bloques opcionales o repetidos:

```hcl
resource "aws_security_group" "main" {
  name = "${local.name_prefix}-sg"

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }
}
```

### 9.3 `lifecycle`

Usar deliberadamente, nunca por defecto:

```hcl
resource "aws_rds_cluster" "main" {
  # ...
  lifecycle {
    prevent_destroy = true                     # Producción crítica
    ignore_changes  = [master_password]        # Gestionado fuera de TF
  }
}
```

- `prevent_destroy = true` en recursos productivos cuya pérdida sea inaceptable (RDS, Aurora, KMS keys, S3 buckets con datos críticos).
- `ignore_changes` con lista explícita, **nunca `all`** salvo recursos importados que no se gestionan activamente.
- `create_before_destroy = true` para recursos sin downtime tolerance (Launch Templates, ASGs, Target Groups).

### 9.4 Locals

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Cálculos de subnetting una sola vez
  private_subnet_cidrs = [
    for idx, az in var.availability_zones :
    cidrsubnet(var.vpc_cidr, 8, idx)
  ]
}
```

- Locals para valores derivados o repetidos. Si un local se usa una sola vez, considerar inline.
- No abusar — un módulo con 50 locals indica mala separación de responsabilidades.

### 9.5 `depends_on`

- Por defecto, **no** usar. Terraform infiere dependencias por referencia.
- Solo cuando hay dependencias **implícitas** que el grafo no puede ver (ej: una IAM policy que debe estar antes de que un servicio asuma un rol que no referencia directamente esa policy).
- Documentar cada `depends_on` con un comentario que explique la dependencia implícita.

---

## 10. Toolchain de validación (shift-left)

### 10.1 Pre-commit hooks

`.pre-commit-config.yaml` mínimo:

```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
      - id: terraform_trivy            # absorbió tfsec en 2024
        args:
          - --args=--severity HIGH,CRITICAL
      - id: terraform_docs
        args:
          - --hook-config=--path-to-file=README.md
          - --hook-config=--add-to-existing-file=true
```

### 10.2 Herramientas

| Tool | Qué cubre | Cuándo correr |
|---|---|---|
| `terraform fmt` | Formato canónico | Pre-commit + CI |
| `terraform validate` | Sintaxis y schema | Pre-commit + CI (post `init`) |
| `tflint` | Reglas de provider, deprecations, naming | Pre-commit + CI |
| `trivy config` (incluye tfsec) | Misconfigurations de seguridad | Pre-commit + CI + dispatch periódico |
| `checkov` | Compliance (CIS, PCI, HIPAA) | CI obligatorio en main |
| `terraform-docs` | Generación automática de README | Pre-commit |
| `terraform plan` | Verificación funcional contra estado actual | CI en cada PR; no en pre-commit |
| `terraform test` | Tests nativos (`*.tftest.hcl`) | CI (módulos críticos) |

### 10.3 `.tflint.hcl` ejemplo

```hcl
plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"

  deep_check = false
}

config {
  format = "compact"
  module = true
}

rule "terraform_required_version"   { enabled = true }
rule "terraform_required_providers" { enabled = true }
rule "terraform_naming_convention"  { enabled = true }
rule "terraform_unused_declarations" { enabled = true }
rule "terraform_documented_outputs" { enabled = true }
rule "terraform_documented_variables" { enabled = true }
```

### 10.4 CI/CD

Pipeline mínimo en cada PR contra `main`:

1. `terraform fmt -check -recursive`
2. `terraform init -backend=false` (sin tocar el backend)
3. `terraform validate`
4. `tflint --recursive`
5. `trivy config .` o `tfsec .`
6. `checkov -d .` (con `--soft-fail` solo si hay un breaking acordado)
7. `terraform plan -out=tfplan` contra el ambiente correspondiente
8. **Approval humano** antes de `terraform apply` en `staging`/`prod`.

---

## 11. Workflow operativo

### 11.1 Cambios en producción

1. PR con cambio + plan adjunto (output de `terraform plan` en el PR).
2. Revisión por al menos 1 reviewer (2 para cambios que tocan IAM, KMS, network o data stores).
3. Merge dispara pipeline que aplica al ambiente target.
4. Apply en producción **siempre** detrás de un approval manual, nunca auto-apply directo.
5. Output del apply se archiva (logs CI + estado en backend).

### 11.2 Drift detection

- Job programado (CloudWatch Events / scheduled GitHub Action) que corre `terraform plan` contra `prod` cada N horas.
- Si hay drift, alerta a Slack/PagerDuty. Drift se reconcilia importando el cambio o destruyéndolo.

### 11.3 Importación de recursos existentes

```hcl
# Terraform >= 1.5 usar import block (declarativo)
import {
  to = aws_s3_bucket.legacy
  id = "my-existing-bucket-name"
}

resource "aws_s3_bucket" "legacy" {
  bucket = "my-existing-bucket-name"
  # configuración existente
}
```

- `import` block declarativo es preferido sobre `terraform import` CLI.
- Después del primer apply exitoso, el `import` block se puede dejar (es idempotente) o eliminar.

### 11.4 Rollback

- **No hay** `terraform rollback` nativo. Rollback = revertir el commit + apply.
- Para cambios destructivos, usar `terraform plan -destroy` y confirmar antes.
- `prevent_destroy` lifecycle en recursos críticos.
- Para estado corrupto: backup del state desde S3 versioning + `terraform state push` con cuidado extremo.

---

## 12. Testing

### 12.1 Native test framework (Terraform 1.6+)

`tests/basic.tftest.hcl`:

```hcl
variables {
  environment = "test"
  vpc_cidr    = "10.99.0.0/16"
}

run "validates_vpc_creation" {
  command = plan

  assert {
    condition     = aws_vpc.main.cidr_block == "10.99.0.0/16"
    error_message = "VPC CIDR did not match input"
  }
}

run "validates_subnet_count" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Expected 3 private subnets"
  }
}
```

- Usar `command = plan` para validaciones rápidas (sin crear recursos).
- Usar `command = apply` (con providers mock o cuenta sandbox) solo para módulos críticos donde la validación de schema no basta.

### 12.2 Terratest (Go) para módulos públicos

Cuando el módulo lo consume otra organización, agregar tests Terratest que hagan `apply`/`destroy` real en una cuenta sandbox y verifiquen el comportamiento end-to-end.

---

## 13. Costos

- Tags de `CostCenter` y `Project` obligatorios para attribution en Cost Explorer.
- `infracost` en CI para PRs que tocan recursos costosos (RDS, Aurora, ElastiCache, NAT Gateways, large EC2):

```yaml
- name: Infracost diff
  run: infracost diff --path=. --compare-to=infracost-base.json
```

- Producción: revisar mensualmente cost anomalies vs forecast. Anomalías >20% disparan análisis IaC + actual.

---

## 14. Documentación

### 14.1 README por módulo (auto-generado)

```markdown
# Module: aurora-cluster

<!-- BEGIN_TF_DOCS -->
## Requirements
| Name | Version |
|------|---------|
| terraform | >= 1.9.0 |
| aws | ~> 5.70 |

## Inputs
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| ... |
<!-- END_TF_DOCS -->
```

- `terraform-docs markdown table --output-file README.md --output-mode inject .`
- Auto-actualizado en pre-commit.

### 14.2 ADRs

Decisiones arquitectónicas no triviales (elección de backend, módulo público vs propio, patrón de multi-account) van como ADR (`docs/adr/NNN-titulo.md`) referenciado desde el código.

---

## 15. Antipatrones — qué **no** hacer

| Antipatrón | Por qué duele | Alternativa |
|---|---|---|
| `version = "latest"` o sin pinning | Builds no reproducibles, breaking changes silenciosos | Pessimistic constraint `~>` |
| Estado local en producción | Pérdida de estado, sin colaboración | S3 backend con locking |
| Secretos en `.tfvars` | Filtrados al historial git | Secrets Manager / SSM via data source |
| `count = length(var.list)` con cambios en medio | Recreación masiva de recursos | `for_each` con map/set |
| `*` en IAM Action o Resource | Permisos excesivos, hallazgo en pentest | Acción y resource específicos |
| `terraform apply --auto-approve` en prod sin approval | Cambios irreversibles sin revisión | Plan reviewable + approval |
| Recursos en consola "para una emergencia" | Drift permanente, estado divergente | Cambio vía Terraform o `terraform import` posterior |
| Módulo gigante (>50 recursos, >1500 líneas) | Plan lento, blast radius enorme | Dividir por dominio funcional |
| Anidamiento profundo de módulos | Difícil de razonar y debuggear | Composición plana en root |
| Outputs sin `description` | Documentación inservible para consumidores | `description` obligatorio |
| Provider config dentro de child module | Imposible de override desde caller | Provider solo en root |
| `ignore_changes = all` | Estado y realidad totalmente desincronizados | Lista explícita de atributos |

---

## 16. Checklist rápido para code review

Al revisar un PR de Terraform, validar:

- [ ] `terraform fmt` aplicado (CI lo confirma).
- [ ] `versions.tf` con `required_version` y `required_providers` pinneados.
- [ ] Variables nuevas tienen `description`, `type`, y validation cuando aplica.
- [ ] Variables sensibles marcadas `sensitive = true`.
- [ ] Outputs nuevos tienen `description`.
- [ ] Sin secretos en HCL ni en `.tfvars` versionados.
- [ ] IAM policies sin `*` (o con justificación inline).
- [ ] Tags estándar via `default_tags`.
- [ ] Cifrado at-rest activo (KMS donde aplica).
- [ ] Recursos críticos con `prevent_destroy = true`.
- [ ] Plan adjunto al PR coincide con el cambio descrito.
- [ ] `tflint` y `trivy`/`checkov` sin findings nuevos (HIGH/CRITICAL).
- [ ] README del módulo actualizado (si cambió interface).
- [ ] Tests `*.tftest.hcl` actualizados o agregados para módulos críticos.

---

## 17. Referencias

- [HashiCorp Developer — Terraform Modules](https://developer.hashicorp.com/terraform/language/modules) — guía oficial sobre módulos.
- [HashiCorp Developer — Module Creation Pattern](https://developer.hashicorp.com/terraform/tutorials/modules/pattern-module-creation) — pattern recomendado para crear módulos.
- [HashiCorp Developer — Well-Architected Framework: Reusable Modules](https://developer.hashicorp.com/well-architected-framework/define-and-automate-processes/define/modules) — diseño de módulos reutilizables.
- [AWS Prescriptive Guidance — Terraform AWS Provider Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/introduction.html) — guía oficial AWS.
- [AWS Prescriptive Guidance — Code Base Structure](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/structure.html) — estructura de repositorio recomendada.
- [AWS Prescriptive Guidance — Security](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/security.html) — recomendaciones de seguridad.
- [AWS Prescriptive Guidance — Backend](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html) — backend remoto.
- [AWS Blog — Best practices for managing Terraform State files in AWS CI/CD Pipeline](https://aws.amazon.com/blogs/devops/best-practices-for-managing-terraform-state-files-in-aws-ci-cd-pipeline/) — state en CI/CD.
- [AWS Blog — Shift-Left Tag Compliance using AWS Organizations and Terraform](https://aws.amazon.com/blogs/mt/shift-left-tag-compliance-using-aws-organizations-and-terraform/) — tag compliance.
- [pre-commit-terraform (antonbabenko)](https://github.com/antonbabenko/pre-commit-terraform) — hooks de pre-commit.
- [HashiCorp Help Center — Organising Terraform and Application Code](https://support.hashicorp.com/hc/en-us/articles/45101629429523-Best-Practices-Organising-Terraform-and-Application-Code) — monorepo vs polyrepo.

> Contenido reformulado para cumplir con licencias de las fuentes originales. Las referencias enlazan al material canónico.
