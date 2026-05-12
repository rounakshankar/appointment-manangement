###############################################################################
# Outputs - printed after terraform apply
###############################################################################

output "frontend_public_ip" {
  description = "Frontend EC2 public IP - open this in a browser."
  value       = aws_eip.frontend.public_ip
}

output "backend_public_ip" {
  description = "Backend EC2 public IP - for SSH and direct API testing."
  value       = aws_eip.backend.public_ip
}

output "backend_private_ip" {
  description = "Backend EC2 private IP - used by frontend Nginx proxy."
  value       = aws_instance.backend.private_ip
}

output "app_url" {
  description = "Main entry point - open this in a browser."
  value       = "http://${aws_eip.frontend.public_ip}"
}

output "api_health_url" {
  description = "Backend API health check."
  value       = "http://${aws_eip.backend.public_ip}:8000/health"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint."
  value       = aws_db_instance.postgres.address
}

output "rds_database_name" {
  description = "PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "ssh_backend" {
  description = "SSH command for backend EC2."
  value       = "ssh -i ~/.ssh/${var.ec2_key_pair_name}.pem ubuntu@${aws_eip.backend.public_ip}"
}

output "ssh_frontend" {
  description = "SSH command for frontend EC2."
  value       = "ssh -i ~/.ssh/${var.ec2_key_pair_name}.pem ubuntu@${aws_eip.frontend.public_ip}"
}

output "backend_logs" {
  description = "Command to tail backend API logs."
  value       = "ssh -i ~/.ssh/${var.ec2_key_pair_name}.pem ubuntu@${aws_eip.backend.public_ip} 'sudo journalctl -u cacms-api -f'"
}

output "frontend_logs" {
  description = "Command to tail frontend bootstrap log."
  value       = "ssh -i ~/.ssh/${var.ec2_key_pair_name}.pem ubuntu@${aws_eip.frontend.public_ip} 'tail -f /var/log/cacms-frontend-bootstrap.log'"
}
