variable "aws_region" {
  description = "Región de AWS donde se despliega la base."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefijo de nombres de los recursos."
  type        = string
  default     = "hack-saltillo-db"
}

variable "environment" {
  description = "Ambiente (dev, demo, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC compartida (RDS + ECS)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "create_nat_gateway" {
  description = "Crea NAT para dar salida a internet a las subredes privadas (necesario si el ECS corre en privadas). Cuesta ~$32/mes."
  type        = bool
  default     = false
}

variable "admin_cidrs" {
  description = "IPs opcionales con acceso directo a PostgreSQL (p. ej. tu laptop para correr Liquibase). La app entra por SG, no las necesita. Ej: [\"201.163.3.86/32\"]."
  type        = list(string)
  default     = []
}

variable "db_name" {
  description = "Nombre de la base inicial."
  type        = string
  default     = "inventario"
}

variable "db_master_username" {
  description = "Usuario maestro de PostgreSQL."
  type        = string
  default     = "inventario"
}

variable "db_port" {
  description = "Puerto de PostgreSQL."
  type        = number
  default     = 5432
}

variable "db_engine_version" {
  description = "Versión mayor de PostgreSQL (RDS elige la menor más reciente)."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Clase de la instancia RDS. t4g.micro es barata (Graviton)."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Almacenamiento en GB (mínimo 20 para gp3)."
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Habilita Multi-AZ (más caro, alta disponibilidad)."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Días de retención de backups automáticos (0 los desactiva)."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Protección contra borrado accidental. Pon true en producción."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Si true, no toma snapshot final al destruir (útil en dev)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags adicionales para los recursos."
  type        = map(string)
  default     = {}
}
