resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_iam_role" "apprunner_access_role" {
  name = "${var.project_name}-apprunner-ecr-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr_access" {
  role       = aws_iam_role.apprunner_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

resource "aws_apprunner_service" "app" {
  service_name = var.project_name

  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access_role.arn
    }

    auto_deployments_enabled = false

    image_repository {
      image_identifier      = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      image_repository_type = "ECR"

      image_configuration {
        port = "3000"
        runtime_environment_variables = {
          OPENAI_API_KEY              = var.openai_api_key
          OPENAI_MODEL                = var.openai_model
          GUARDRAIL_MODEL             = var.guardrail_model
          MCP_SERVER_URL              = var.mcp_server_url
          AUTH_TOKEN_TTL_SECONDS      = tostring(var.auth_token_ttl_seconds)
          MAX_INPUT_CHARS             = tostring(var.max_input_chars)
          HISTORY_CONTEXT_LIMIT       = tostring(var.history_context_limit)
          LOG_LEVEL                   = var.log_level
          ENABLE_OPENAI_TRACING       = "true"
          CORS_ALLOWED_ORIGINS        = "*"
          BACKEND_API_URL             = "http://127.0.0.1:8000"
          DATABASE_URL                = "postgresql+asyncpg://postgres:postgres@127.0.0.1:5432/meridian_chatbot"
          NEXT_PUBLIC_BACKEND_API_URL = ""
        }
      }
    }
  }

  instance_configuration {
    cpu    = var.apprunner_cpu
    memory = var.apprunner_memory
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }
}
