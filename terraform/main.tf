# VPC COMPARTIDA: subredes públicas (ECS/ALB/NAT) y privadas (RDS).
# La RDS es privada y solo acepta conexiones desde el SG de la app (SG->SG).
# Así la app NO depende de IPs: únicamente adjunta `app_security_group_id` a las tareas ECS.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name          = "${var.project}-${var.environment}"
  azs           = slice(data.aws_availability_zones.available.names, 0, 2)
  public_cidrs  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_cidrs = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# --- Red -------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${local.name}-public-${count.index + 1}" })
}

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, { Name = "${local.name}-private-${count.index + 1}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, { Name = "${local.name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT opcional: las tareas ECS en subredes privadas necesitan salida a internet para
# jalar imágenes de ECR, Secrets Manager, etc. Si pones el ECS en subredes públicas con IP
# pública, puedes dejarlo en false. (NAT cuesta ~$32/mes + tráfico).
resource "aws_eip" "nat" {
  count  = var.create_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.name}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  count         = var.create_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.this]

  tags = merge(local.tags, { Name = "${local.name}-nat" })
}

resource "aws_route_table" "private" {
  count  = var.create_nat_gateway ? 1 : 0
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[0].id
  }

  tags = merge(local.tags, { Name = "${local.name}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count          = var.create_nat_gateway ? length(aws_subnet.private) : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

# --- Seguridad -------------------------------------------------------------
# Adjunta este SG a las tareas ECS; con eso la app entra a la RDS sin manejar IPs.
resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "SG para las tareas de la app (ECS); adjuntar al servicio"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Salida libre"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-app" })
}

resource "aws_security_group" "rds" {
  name = "${local.name}-rds"
  # OJO: no cambies la descripción de un SG ya creado; AWS obliga a recrearlo.
  # (Mantener el texto original evita reemplazar el SG que ya usa la RDS.)
  description = "Acceso a PostgreSQL restringido por IP"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "PostgreSQL desde el SG de la app"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # Acceso admin OPCIONAL (p.ej. tu laptop para correr Liquibase). La app NO lo necesita.
  dynamic "ingress" {
    for_each = length(var.admin_cidrs) > 0 ? [1] : []
    content {
      description = "Acceso admin opcional"
      from_port   = var.db_port
      to_port     = var.db_port
      protocol    = "tcp"
      cidr_blocks = var.admin_cidrs
    }
  }

  egress {
    description = "Salida libre"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-rds" })
}

resource "aws_db_subnet_group" "this" {
  name = "${local.name}-subnets"
  # La RDS ya está creada en las subredes públicas (subnet group original). AWS no permite
  # quitar subredes "en uso" sin recrear la instancia, así que la mantenemos aquí; de todos
  # modos la RDS es privada (publicly_accessible = false) y solo la alcanza el SG de la app.
  # Las subredes privadas quedan disponibles para las tareas ECS.
  subnet_ids = aws_subnet.public[*].id

  tags = merge(local.tags, { Name = "${local.name}-subnets" })
}

# --- Base de datos ---------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier     = "${local.name}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_master_username
  port     = var.db_port

  # Contraseña maestra gestionada por RDS en AWS Secrets Manager (no queda en el state).
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot
  apply_immediately       = true

  auto_minor_version_upgrade = true

  tags = merge(local.tags, { Name = "${local.name}-postgres" })
}
