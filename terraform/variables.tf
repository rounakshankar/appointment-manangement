###############################################################################
# Input variables - set values in terraform.tfvars (never commit that file)
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Short project name used as a prefix for all resource names."
  type        = string
  default     = "cacms"
}

variable "environment" {
  description = "Deployment environment label."
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
  description = "Name of an existing EC2 key pair for SSH access."
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH into both EC2 instances."
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
  description = "PostgreSQL database name."
  type        = string
  default     = "cacms"
}

variable "rds_username" {
  description = "PostgreSQL master username."
  type        = string
  default     = "cacms_user"
}

variable "rds_password" {
  description = "PostgreSQL master password. Must be at least 8 characters."
  type        = string
  sensitive   = true
}

variable "rds_allocated_storage" {
  description = "RDS storage in GB. Free tier allows up to 20 GB."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# App secrets
# ---------------------------------------------------------------------------

variable "jwt_secret" {
  description = "JWT signing secret."
  type        = string
  sensitive   = true
}

variable "superadmin_token" {
  description = "Static token for the super-admin API."
  type        = string
  sensitive   = true
}

variable "backup_encryption_key" {
  description = "AES backup encryption key."
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
# Git
# ---------------------------------------------------------------------------

variable "git_repo_url" {
  description = "Git repository URL (public HTTPS)."
  type        = string
  default     = "https://github.com/rounakshankar/appointment-manangement.git"
}

variable "git_branch" {
  description = "Git branch to deploy."
  type        = string
  default     = "main"
}
