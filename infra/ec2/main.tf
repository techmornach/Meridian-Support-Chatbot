data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "default_az" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availability-zone"
    values = [var.availability_zone]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_route53_zone" "main" {
  count        = var.create_route53_records ? 1 : 0
  name         = "${var.hosted_zone_name}."
  private_zone = false
}

locals {
  normalized_hosted_zone_name = trimspace(var.hosted_zone_name)
  frontend_domain = trimspace(var.frontend_domain) != "" ? trimspace(var.frontend_domain) : (
    local.normalized_hosted_zone_name != "" ? "${var.frontend_subdomain}.${local.normalized_hosted_zone_name}" : ""
  )
  backend_domain = trimspace(var.backend_domain) != "" ? trimspace(var.backend_domain) : (
    local.normalized_hosted_zone_name != "" ? "${var.backend_subdomain}.${local.normalized_hosted_zone_name}" : ""
  )
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for Meridian EC2 deployment"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "frontend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.frontend_instance_type
  subnet_id                   = data.aws_subnet.default_az.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name == "" ? null : var.ssh_key_name

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update
    apt-get install -y ca-certificates curl git
    mkdir -p /opt/meridian
    chown -R ubuntu:ubuntu /opt/meridian
  EOF

  tags = {
    Name = "${var.project_name}-frontend-ec2"
  }
}

resource "aws_instance" "backend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.backend_instance_type
  subnet_id                   = data.aws_subnet.default_az.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name == "" ? null : var.ssh_key_name

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update
    apt-get install -y ca-certificates curl git
    mkdir -p /opt/meridian
    chown -R ubuntu:ubuntu /opt/meridian
  EOF

  tags = {
    Name = "${var.project_name}-backend-ec2"
  }
}

resource "aws_eip" "frontend" {
  domain   = "vpc"
  instance = aws_instance.frontend.id
}

resource "aws_eip" "backend" {
  domain   = "vpc"
  instance = aws_instance.backend.id
}

resource "aws_route53_record" "frontend" {
  count   = var.create_route53_records ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = local.frontend_domain
  type    = "A"
  ttl     = 60
  records = [aws_eip.frontend.public_ip]

  lifecycle {
    precondition {
      condition     = local.frontend_domain != ""
      error_message = "frontend_domain (or hosted_zone_name + frontend_subdomain) must be set when create_route53_records=true."
    }
  }
}

resource "aws_route53_record" "backend" {
  count   = var.create_route53_records ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = local.backend_domain
  type    = "A"
  ttl     = 60
  records = [aws_eip.backend.public_ip]

  lifecycle {
    precondition {
      condition     = local.backend_domain != ""
      error_message = "backend_domain (or hosted_zone_name + backend_subdomain) must be set when create_route53_records=true."
    }
  }
}
