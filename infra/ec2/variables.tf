variable "aws_region" {
  description = "AWS region for EC2 resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project prefix for resources."
  type        = string
  default     = "meridian-support-chatbot"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.small"
}

variable "ssh_key_name" {
  description = "Optional EC2 key pair name."
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to instance."
  type        = string
  default     = "0.0.0.0/0"
}

variable "hosted_zone_name" {
  description = "Route53 hosted zone name."
  type        = string
  default     = "home.jaraflytech.com"
}

variable "subdomain" {
  description = "Subdomain label for app endpoint."
  type        = string
  default     = "meridian"
}

variable "availability_zone" {
  description = "Availability zone for the EC2 instance."
  type        = string
  default     = "us-east-1a"
}
