###############################################################################
# EC2 — Ubuntu 22.04, t2.micro (free tier)
# user_data bootstraps Docker, clones the repo, writes .env.production,
# and starts the app via docker-compose.aws.yml
###############################################################################

# Latest Ubuntu 22.04 LTS AMI (official Canonical)
data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Elastic IP — gives a stable public IP that survives EC2 stop/start
# ---------------------------------------------------------------------------

resource "aws_eip" "api" {
  instance = aws_instance.api.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project}-eip"
    Project     = var.project
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# EC2 instance
# ---------------------------------------------------------------------------

resource "aws_instance" "api" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = var.ec2_instance_type
  key_name               = var.ec2_key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]

  # 20 GB root volume (free tier includes 30 GB EBS)
  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  # Bootstrap script — runs once on first boot
  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    project               = var.project
    git_repo_url          = var.git_repo_url
    git_branch            = var.git_branch
    environment           = var.environment
    database_url          = "postgresql+asyncpg://${var.rds_username}:${var.rds_password}@${aws_db_instance.postgres.address}:5432/${var.rds_db_name}"
    jwt_secret            = var.jwt_secret
    backup_encryption_key = var.backup_encryption_key
    sentry_dsn            = var.sentry_dsn
    # CORS_ORIGINS is set after EIP is known — updated by a second provisioner
    cors_origins_placeholder = "REPLACE_WITH_EIP_AFTER_APPLY"
  })

  # Wait for RDS to be available before starting EC2 bootstrap
  depends_on = [aws_db_instance.postgres]

  tags = {
    Name        = "${var.project}-api"
    Project     = var.project
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# Null resource — updates CORS_ORIGINS in .env.production with the real EIP
# after both EC2 and EIP are created. Runs via SSH.
# ---------------------------------------------------------------------------

resource "null_resource" "update_cors" {
  triggers = {
    eip = aws_eip.api.public_ip
  }

  depends_on = [aws_eip.api, aws_instance.api]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = aws_eip.api.public_ip
      user        = "ubuntu"
      private_key = file("~/.ssh/${var.ec2_key_pair_name}.pem")
      timeout     = "5m"
    }

    inline = [
      # Wait for user_data to finish
      "until [ -f /home/ubuntu/cacms/.env.production ]; do sleep 5; done",
      # Replace the placeholder with the real EIP
      "sed -i 's|REPLACE_WITH_EIP_AFTER_APPLY|http://${aws_eip.api.public_ip}:8000|g' /home/ubuntu/cacms/.env.production",
      # Restart the API to pick up the new CORS_ORIGINS
      "cd /home/ubuntu/cacms && docker compose -f docker-compose.aws.yml --env-file .env.production up -d --force-recreate api",
      "echo 'CORS updated to http://${aws_eip.api.public_ip}:8000'"
    ]
  }
}
