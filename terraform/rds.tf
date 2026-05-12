###############################################################################
# RDS — PostgreSQL 16, db.t3.micro (free tier)
# NOT publicly accessible — EC2 only via private subnet
###############################################################################

resource "aws_db_subnet_group" "main" {
  name        = "${var.project}-db-subnet-group"
  description = "CACMS RDS subnet group (two private AZs)"
  subnet_ids  = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name        = "${var.project}-db-subnet-group"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project}-db"

  # Engine
  engine               = "postgres"
  engine_version       = "16"
  instance_class       = var.rds_instance_class

  # Storage — 20 GB is the free tier max
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_allocated_storage # disable autoscaling on free tier
  storage_type          = "gp2"
  storage_encrypted     = true

  # Credentials
  db_name  = var.rds_db_name
  username = var.rds_username
  password = var.rds_password

  # Network — private, no public access
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false # free tier: single AZ only

  # Backups — 7-day retention, free tier includes backup storage up to DB size
  backup_retention_period = 7
  backup_window           = "02:00-03:00" # UTC — 7:30 AM IST
  maintenance_window      = "Mon:03:00-Mon:04:00"

  # Deletion protection — set to true before real production use
  deletion_protection = false
  skip_final_snapshot = true # set to false before real production use

  # Performance Insights — disabled on free tier (costs money)
  performance_insights_enabled = false

  tags = {
    Name        = "${var.project}-db"
    Project     = var.project
    Environment = var.environment
  }
}
