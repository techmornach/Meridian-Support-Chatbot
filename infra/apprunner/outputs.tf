output "ecr_repository_url" {
  description = "ECR repository URL for pushing container images."
  value       = aws_ecr_repository.app.repository_url
}

output "apprunner_service_arn" {
  description = "App Runner service ARN."
  value       = aws_apprunner_service.app.arn
}

output "apprunner_service_url" {
  description = "Public URL of the App Runner service."
  value       = aws_apprunner_service.app.service_url
}
