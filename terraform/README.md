# Terraform — RDS PostgreSQL (privada, para ECS)

Aprovisiona en AWS una **VPC compartida** (subredes públicas y privadas) y una **RDS PostgreSQL
privada**. La app (**ECS**) se conecta por **Security Group (SG→SG)**: nunca manejas IPs.

- Región por defecto: `us-east-1`.
- RDS: `db.t4g.micro`, 20 GB gp3, single-AZ, `publicly_accessible = false`.
- La contraseña maestra la **genera y administra RDS** en **AWS Secrets Manager**.
- Terraform **no** aplica migraciones (eso es Liquibase, ver abajo).

## Arquitectura

```
                 VPC 10.20.0.0/16
  ┌─────────────────────────────────────────────────────────┐
  │  subredes públicas            subredes privadas          │
  │  (ALB / NAT / ECS)            (RDS)                      │
  │                                                          │
  │  ECS (task) ── SG: ...-app ──▶ 5432 ──▶ RDS (SG: ...-rds)│
  └─────────────────────────────────────────────────────────┘
```

- `app_security_group_id`: **adjúntalo a las tareas ECS** (en el repo de la API). Con eso la app
  entra a la RDS sin abrir IPs.
- `db_security_group_id`: SG de la base (solo acepta `5432` **desde el SG de la app**).
- `private_subnet_ids` / `public_subnet_ids` / `vpc_id`: para que el ECS se despliegue en la
  misma red.

## Requisitos

- Terraform `>= 1.5`.
- AWS CLI configurado (`aws configure`) o variables de entorno con credenciales.

## Uso

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Salidas para el repo de la API / ECS

```bash
terraform output app_security_group_id
terraform output private_subnet_ids
terraform output vpc_id
terraform output db_address
terraform output -raw db_jdbc_url
```

En el ECS service, en `network_configuration`:

- `subnets = private_subnet_ids` (o las públicas si usas IP pública),
- `security_groups = [app_security_group_id]`.

Obtener la contraseña maestra (para la app, en runtime):

```bash
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw db_master_user_secret_arn)" \
  --query SecretString --output text
```

## Migraciones (Liquibase)

La RDS es privada: **no tiene IP pública**, así que ya **no puedes correr Liquibase desde tu
laptop directamente** (el `admin_cidrs` solo serviría si hubiera endpoint público). Opciones:

- **Recomendado**: correr las migraciones desde **dentro de la VPC** (una tarea ECS,
  CodeBuild, o una EC2 en la misma VPC con el `app_security_group`).
- **Desde tu laptop**: agregar un **bastión con SSM** y usar *port forwarding*:
  `aws ssm start-session --document-name AWS-StartPortForwardingSessionToRemoteHost ...`,
  luego apuntar Liquibase a `localhost:5432`.

Comando de Liquibase una vez con acceso a la red:

```bash
liquibase --defaults-file=../liquibase/liquibase.properties \
  --url="$(terraform output -raw db_jdbc_url)" \
  --username="$(terraform output -raw db_master_username)" \
  --password="<password de Secrets Manager>" \
  --search-path=../liquibase/changelog \
  --changelog-file=db.changelog-master.yaml \
  update
```

> Por defecto Liquibase aplica **todos** los changesets (esquema + datos de ejemplo). Para
> aplicar **solo el esquema**, agrega `--context-filter=base`.

## Variables útiles (`terraform.tfvars`)

| Variable | Descripción |
|---|---|
| `create_nat_gateway` | `true` da salida a internet a las subredes privadas (necesario si el ECS corre en privadas para jalar imágenes/Secrets). Cuesta ~$32/mes. `false` si el ECS va en subredes públicas. |
| `admin_cidrs` | IPs opcionales para acceso directo (solo aplica si hubiera endpoint público; con la BD privada usa túnel/ECS). |
| `multi_az`, `deletion_protection`, `backup_retention_period` | Endurecer para producción. |

## Seguridad

- La RDS **no es pública** y solo acepta conexiones del **SG de la app** (SG→SG).
- **No** subas `terraform.tfvars` ni `terraform.tfstate` al repo (están en `.gitignore`).
- Para producción: `multi_az = true`, `deletion_protection = true`, `backup_retention_period >= 7`.

## Destruir

```bash
terraform destroy
```

Con `skip_final_snapshot = true` (dev) no se conserva snapshot.

## Archivos

| Archivo | Qué es |
|---|---|
| `versions.tf` | Versión de Terraform y provider AWS. |
| `variables.tf` | Variables (región, red, base, costos). |
| `main.tf` | VPC, subredes, Security Groups y RDS. |
| `outputs.tf` | IDs de red/SG y datos de conexión. |
| `terraform.tfvars.example` | Plantilla de variables. |
