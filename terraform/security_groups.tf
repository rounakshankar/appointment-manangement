###############################################################################
# Security Groups
# Architecture:
#   Internet -> Frontend EC2 (80/443) -> Backend EC2 (8000) -> RDS (5432)
#   SSH allowed to both EC2s from ssh_allowed_cidr
###############################################################################

# ---------------------------------------------------------------------------
# Frontend EC2 security group
# Public-facing: accepts HTTP/HTTPS from anywhere, SSH from admin IP
# ---------------------------------------------------------------------------

resource "aws_security_group" "frontend" {
  name        = "${var.project}-frontend-sg"
  description = "CACMS Frontend - HTTP HTTPS and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-frontend-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# Backend EC2 security group
# Private-facing: only accepts API traffic from the frontend EC2
# ---------------------------------------------------------------------------

resource "aws_security_group" "backend" {
  name        = "${var.project}-backend-sg"
  description = "CACMS Backend - API from frontend only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "FastAPI from frontend EC2 only"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-backend-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# RDS security group
# Only accepts connections from the backend EC2
# ---------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "CACMS RDS - PostgreSQL from backend only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from backend EC2 only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-rds-sg"
    Project     = var.project
    Environment = var.environment
  }
}
