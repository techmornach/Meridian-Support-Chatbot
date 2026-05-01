output "frontend_instance_id" {
  value       = aws_instance.frontend.id
  description = "Frontend EC2 instance ID."
}

output "backend_instance_id" {
  value       = aws_instance.backend.id
  description = "Backend EC2 instance ID."
}

output "frontend_public_ip" {
  value       = aws_eip.frontend.public_ip
  description = "Public IP for frontend EC2."
}

output "backend_public_ip" {
  value       = aws_eip.backend.public_ip
  description = "Public IP for backend EC2."
}

output "frontend_domain" {
  value       = local.frontend_domain != "" ? local.frontend_domain : aws_eip.frontend.public_ip
  description = "Frontend domain if configured, otherwise frontend public IP."
}

output "backend_domain" {
  value       = local.backend_domain != "" ? local.backend_domain : aws_eip.backend.public_ip
  description = "Backend domain if configured, otherwise backend public IP."
}

output "frontend_base_url" {
  value       = local.frontend_domain != "" ? "https://${local.frontend_domain}" : "http://${aws_eip.frontend.public_ip}"
  description = "Frontend base URL."
}

output "backend_base_url" {
  value       = local.backend_domain != "" ? "https://${local.backend_domain}" : "http://${aws_eip.backend.public_ip}"
  description = "Backend base URL."
}

output "frontend_ssh_command" {
  value       = "ssh ubuntu@${aws_eip.frontend.public_ip}"
  description = "SSH command for frontend EC2."
}

output "backend_ssh_command" {
  value       = "ssh ubuntu@${aws_eip.backend.public_ip}"
  description = "SSH command for backend EC2."
}
