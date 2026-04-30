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
  value       = aws_route53_record.frontend.fqdn
  description = "Frontend domain."
}

output "backend_domain" {
  value       = aws_route53_record.backend.fqdn
  description = "Backend domain."
}

output "frontend_ssh_command" {
  value       = "ssh ubuntu@${aws_eip.frontend.public_ip}"
  description = "SSH command for frontend EC2."
}

output "backend_ssh_command" {
  value       = "ssh ubuntu@${aws_eip.backend.public_ip}"
  description = "SSH command for backend EC2."
}
