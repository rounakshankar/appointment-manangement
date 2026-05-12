###############################################################################
# Outputs - printed after terraform apply
###############################################################################

output "ec2_public_ip" {
  description = "EC2 Elastic IP - use this in your Flutter build and CORS_ORIGINS."
  value       = aws_eip.api.public_ip
}

output "ec2_instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.api.id
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host only, no port)."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.postgres.port
}

output "rds_database_name" {
  description = "PostgreSQL database name."
  value       = aws_db_instance.postgres.db_name
}

output "api_health_url" {
  description = "Health check URL - open this in a browser to verify deployment."
  value       = "http://${aws_eip.api.public_ip}:8000/health"
}

output "api_docs_url" {
  description = "Swagger UI URL - disable docs_url in production after initial verification."
  value       = "http://${aws_eip.api.public_ip}:8000/docs"
}

output "flutter_build_command" {
  description = "Flutter APK build command with the correct backend URL."
  value       = "flutter build apk --dart-define=BACKEND_URL=http://${aws_eip.api.public_ip}:8000"
}

output "ssh_command" {
  description = "SSH command to connect to EC2."
  value       = "ssh -i ~/.ssh/${var.ec2_key_pair_name}.pem ubuntu@${aws_eip.api.public_ip}"
}

output "seed_owner_command" {
  description = "Command to create the first clinic owner account."
  value       = "ssh -i ~/.ssh/${var.ec2_key_pair_name}.pem ubuntu@${aws_eip.api.public_ip} 'cd ~/cacms && docker compose -f docker-compose.aws.yml --env-file .env.production exec api python scripts/create_owner.py --username owner --password YOUR_PASSWORD --clinic-name \"Your Clinic\"'"
}

output "bootstrap_log_command" {
  description = "Command to view the bootstrap log on EC2."
  value       = "ssh -i ~/.ssh/${var.ec2_key_pair_name}.pem ubuntu@${aws_eip.api.public_ip} 'tail -f /var/log/cacms-bootstrap.log'"
}
