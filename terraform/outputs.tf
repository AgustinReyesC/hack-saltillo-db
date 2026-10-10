# --- Red (para que el ECS y la RDS compartan VPC) --------------------------
output "vpc_id" {
  description = "VPC compartida."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Subredes públicas (ALB / NAT / ECS con IP pública)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Subredes privadas (RDS / ECS)."
  value       = aws_subnet.private[*].id
}

# --- Seguridad -------------------------------------------------------------
output "app_security_group_id" {
  description = "Adjunta este SG a las tareas ECS: así entran a la RDS sin IPs."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "SG de la base (por si otro stack necesita referenciarlo)."
  value       = aws_security_group.rds.id
}

# --- Base de datos ---------------------------------------------------------
output "db_identifier" {
  description = "Identificador de la instancia RDS."
  value       = aws_db_instance.this.identifier
}

output "db_address" {
  description = "Host de conexión."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Puerto de PostgreSQL."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Nombre de la base."
  value       = aws_db_instance.this.db_name
}

output "db_master_username" {
  description = "Usuario maestro."
  value       = aws_db_instance.this.username
}

output "db_connection_string" {
  description = "Cadena para psql (sin password; pídelo a Secrets Manager)."
  value       = "postgresql://${aws_db_instance.this.username}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
}

output "db_jdbc_url" {
  description = "URL JDBC para Liquibase."
  value       = "jdbc:postgresql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
}

output "db_master_user_secret_arn" {
  description = "ARN del secreto en Secrets Manager con la contraseña maestra."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}
