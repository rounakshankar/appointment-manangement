###############################################################################
# EC2 Instances
# - backend: FastAPI + Redis via systemd (no Docker)
# - frontend: Flutter Web served by Nginx, proxies /api/* to backend
###############################################################################

data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"]

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
# Backend EC2 - FastAPI + Redis, no Docker
# ---------------------------------------------------------------------------

resource "aws_instance" "backend" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = var.ec2_instance_type
  key_name               = var.ec2_key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.backend.id]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/backend_user_data.sh.tpl", {
    git_repo_url          = var.git_repo_url
    git_branch            = var.git_branch
    rds_endpoint          = aws_db_instance.postgres.address
    rds_username          = var.rds_username
    rds_password          = var.rds_password
    rds_db_name           = var.rds_db_name
    jwt_secret            = var.jwt_secret
    superadmin_token      = var.superadmin_token
    backup_encryption_key = var.backup_encryption_key
    sentry_dsn            = var.sentry_dsn
    # CORS: frontend public IP is set after both instances are created
    # Updated by null_resource.update_cors below
    cors_origins          = "REPLACE_WITH_FRONTEND_IP"
  })

  depends_on = [aws_db_instance.postgres]

  tags = {
    Name        = "${var.project}-backend"
    Project     = var.project
    Environment = var.environment
    Role        = "backend"
  }
}

resource "aws_eip" "backend" {
  instance = aws_instance.backend.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project}-backend-eip"
    Project     = var.project
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# Frontend EC2 - Flutter Web + Nginx
# Depends on backend so we know the backend private IP for Nginx proxy config
# ---------------------------------------------------------------------------

resource "aws_instance" "frontend" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = var.ec2_instance_type
  key_name               = var.ec2_key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.frontend.id]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/frontend_user_data.sh.tpl", {
    git_repo_url       = var.git_repo_url
    git_branch         = var.git_branch
    # Use private IP so traffic stays within the VPC (no data transfer cost)
    backend_private_ip = aws_instance.backend.private_ip
  })

  depends_on = [aws_instance.backend]

  tags = {
    Name        = "${var.project}-frontend"
    Project     = var.project
    Environment = var.environment
    Role        = "frontend"
  }
}

resource "aws_eip" "frontend" {
  instance = aws_instance.frontend.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project}-frontend-eip"
    Project     = var.project
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# Update CORS on backend after frontend EIP is known
# ---------------------------------------------------------------------------

resource "null_resource" "update_cors" {
  triggers = {
    frontend_eip = aws_eip.frontend.public_ip
  }

  depends_on = [aws_eip.frontend, aws_instance.backend]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = aws_eip.backend.public_ip
      user        = "ubuntu"
      private_key = file("~/.ssh/${var.ec2_key_pair_name}.pem")
      timeout     = "10m"
    }

    inline = [
      # Wait for the API service to be running
      "until systemctl is-active --quiet cacms-api; do echo 'Waiting for cacms-api...'; sleep 10; done",
      # Update CORS_ORIGINS with the real frontend IP
      "sed -i 's|CORS_ORIGINS=.*|CORS_ORIGINS=http://${aws_eip.frontend.public_ip}|' /home/ubuntu/cacms/.env.production",
      # Restart the API to pick up new CORS setting
      "sudo systemctl restart cacms-api",
      "sleep 5",
      "curl -sf http://localhost:8000/health && echo 'API healthy after CORS update'",
      "echo 'CORS updated to http://${aws_eip.frontend.public_ip}'"
    ]
  }
}
