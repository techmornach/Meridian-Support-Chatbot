output "instance_id" {
  value       = aws_instance.app.id
  description = "EC2 instance ID."
}

output "instance_public_ip" {
  value       = aws_eip.app.public_ip
  description = "Public IP for EC2 instance."
}

output "app_domain" {
  value       = aws_route53_record.app.fqdn
  description = "DNS record for the app endpoint."
}

output "ssh_command" {
  value       = "ssh ubuntu@${aws_eip.app.public_ip}"
  description = "Convenience SSH command."
}
