###############################################################################
# Input variables — set values in terraform.tfvars (never commit that file)
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy into. Free tier is per-account, not per-region."
  type        = string
  default     = "ap-south-1" # Mumbai — closest to India; change to us-east-1 etc. if needed
}

variable "project" {
  description = "Short project name used as a prefix for all resource names."
  type        = string
  default     = "cacms"
}

variable "environment" {
  description = "Deployment environment label (production, staging, etc.)."
  type        = string
  default     = "production"
}

# ---------------------------------------------------------------------------
# EC2
# ---------------------------------------------------------------------------

variable "ec2_instance_type" {
  description = "EC2 instance type. t2.micro is free-tier eligible."
  type        = string
  default     = "t2.micro"
}

variable "ec2_key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access. Create one in the AWS console first."
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH into EC2. Use your public IP: curl ifconfig.me"
  type        = string
  # Example: "203.0.113.42/32"
}

variable "api_allowed_cidr" {
  description = "CIDR block allowed to reach port 8000. Use 0.0.0.0/0 for public access."
  type        = string
  default     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

variable "rds_instance_class" {
  description = "RDS instance class. db.t3.micro is free-tier eligible."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_db_name" {
  description = "PostgreSQL database name to create."
  type        = string
  default     = "cacms"
}

variable "rds_username" {
  description = "PostgreSQL master username."
  type        = string
  default     = "cacms_user"
}

variable "rds_password" {
  description = "PostgreSQL master password. Must be at least 8 characters. Store securely."
  type        = string
  sensitive   = true
}

variable "rds_allocated_storage" {
  description = "RDS storage in GB. Free tier allows up to 20 GB."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# App secrets (written to EC2 as /home/ubuntu/cacms/.env.production)
# ---------------------------------------------------------------------------

variable "jwt_secret" {
  description = "JWT signing secret. Generate: python3 -c \"import secrets; print(secrets.token_hex(32))\""
  type        = string
  sensitive   = true
}

variable "backup_encryption_key" {
  description = "AES backup encryption key. Generate: python3 -c \"import secrets; print(secrets.token_hex(32))\""
  type        = string
  sensitive   = true
  default     = ""
}

variable "sentry_dsn" {
  description = "Optional Sentry DSN for error tracking."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Git / deployment
# ---------------------------------------------------------------------------

variable "git_repo_url" {
  description = "Git repository URL to clone on EC2. Use HTTPS for public repos."
  type        = string
  default     = "https://github.com/YOUR_ORG/cacms.git"
}

variable "git_branch" {
  description = "Git branch to deploy."
  type        = string
  default     = "main"
}
