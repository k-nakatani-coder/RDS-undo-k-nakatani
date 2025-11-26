# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

# Private Subnets for Aurora
resource "aws_subnet" "aurora" {
  count             = 3  # Aurora requires at least 2 AZs, 3 for better HA
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-aurora-subnet-${count.index + 1}"
    Type = "Aurora"
  })
}

# Private Subnets for Lambda (将来用に準備だけ)
resource "aws_subnet" "lambda" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-lambda-subnet-${count.index + 1}"
    Type = "Lambda"
  })
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-private-rt"
  })
}

# Route Table Associations
resource "aws_route_table_association" "aurora" {
  count          = length(aws_subnet.aurora)
  subnet_id      = aws_subnet.aurora[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "lambda" {
  count          = length(aws_subnet.lambda)
  subnet_id      = aws_subnet.lambda[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Group for Aurora
resource "aws_security_group" "aurora" {
  name_prefix = "${var.project_name}-${var.environment}-aurora-"
  description = "Security group for Aurora PostgreSQL"
  vpc_id      = aws_vpc.main.id

  # 検証用に一時的にVPC内からのアクセスを許可
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-aurora-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-${var.environment}-aurora-subnet-group"
  subnet_ids = aws_subnet.aurora[*].id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-aurora-subnet-group"
  })
}