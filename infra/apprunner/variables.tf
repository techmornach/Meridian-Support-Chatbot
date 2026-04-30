variable "aws_region" {
  description = "AWS region for App Runner resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project prefix for resource names."
  type        = string
  default     = "meridian-support-chatbot"
}

variable "image_tag" {
  description = "Image tag App Runner should run."
  type        = string
  default     = "latest"
}

variable "apprunner_cpu" {
  description = "App Runner CPU setting."
  type        = string
  default     = "1024"
}

variable "apprunner_memory" {
  description = "App Runner memory setting."
  type        = string
  default     = "2048"
}

variable "openai_api_key" {
  description = "OpenAI API key passed to runtime."
  type        = string
  sensitive   = true
}

variable "mcp_server_url" {
  description = "MCP endpoint URL."
  type        = string
  default     = "https://order-mcp-74afyau24q-uc.a.run.app/mcp"
}

variable "openai_model" {
  description = "OpenAI model used by backend."
  type        = string
  default     = "gpt-4o-mini"
}

variable "guardrail_model" {
  description = "Guardrail model used by backend."
  type        = string
  default     = "gpt-4o-mini"
}

variable "auth_token_ttl_seconds" {
  description = "Session token TTL in seconds."
  type        = number
  default     = 3600
}

variable "max_input_chars" {
  description = "Maximum user message length."
  type        = number
  default     = 4000
}

variable "history_context_limit" {
  description = "Number of messages used as context."
  type        = number
  default     = 30
}

variable "log_level" {
  description = "Backend log level."
  type        = string
  default     = "INFO"
}
