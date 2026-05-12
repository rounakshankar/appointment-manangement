###############################################################################
# Security Groups
###############################################################################

# ---------------------------------------------------------------------------
# EC2 security group
# ---------------------------------------------------------------------------

resource "aws_security_group" "ec2" {
  name        = "${var.project}-ec2-sg"
  description = "CACMS EC2 - SSH and API port"
  vpc_id      = aws_vpc.main.id

  # SSH - restricted to your IP only
  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # API port 8000 - public (restrict to your IP during testing if preferred)
  ingress {
    description = "CACMS API"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.api_allowed_cidr]
  }

  # HTTP 80 — needed for Nginx and Let's Encrypt ACME challenge
  ingress {
    description = "HTTP - Nginx and Lets Encrypt"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS 443 — Nginx TLS termination
  ingress {
    description = "HTTPS - Nginx TLS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound (Docker pulls, apt, git, RDS)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-ec2-sg"
    Project     = var.project
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# RDS security group — only accepts connections from EC2
# ---------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "CACMS RDS - PostgreSQL from EC2 only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
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
