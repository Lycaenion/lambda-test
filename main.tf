terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.99.1"
    }
  }
}
provider "aws" {
    region = "eu-central-1"
}

resource "aws_key_pair" "deployer" {
  key_name = "deployer_key"
  public_key = file("${path.module}/deployer-key.pub")
}

resource "aws_security_group" "ec2_sg" {
  name = "ec2_security_group"
  description = "Allow SSH inbound traffic"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

data "aws_ami" "ubuntu"{
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }

    owners = ["099720109477"] # Canonical
}

# --- Create KMS Key ---
resource "aws_kms_key" "lambda_env_key" {
  description             = "KMS key for encrypting Lambda environment variables"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "lambda_env_key_alias" {
  name          = "alias/lambda-env-key"
  target_key_id = aws_kms_key.lambda_env_key.key_id
}

# --- Grant Lambda Execution Role Access ---
# Replace with your Lambda execution role ARN
data "aws_iam_role" "lambda_exec_role" {
  name = "selenium-test-role-n1fivr7l"
}

resource "aws_kms_key_policy" "lambda_env_key_policy" {
  key_id = aws_kms_key.lambda_env_key.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "lambda-env-key-policy"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowLambdaUseOfTheKey"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_iam_role.lambda_exec_role.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# Get current AWS account for policy
data "aws_caller_identity" "current" {}


resource "aws_instance" "selenium-test" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.ec2_sg.name]

  user_data = <<-EOF
      #!/bin/bash
      set -e

      # Update and install dependencies
      apt-get update -y
      apt-get install -y git docker.io

      # Enable and start Docker
      systemctl enable docker
      systemctl start docker
      usermod -aG docker ubuntu

      # Wait for network and home directory to be ready
      sleep 160

      # Clone the GitHub repo as ubuntu user
      sudo -u ubuntu git clone https://github.com/Lycaenion/lambda-test.git /home/ubuntu/lambda-test

    EOF
  tags = {
    Name = "SeleniumTestInstance"
  }
}

output "ssh_command"  {
  value = "ssh -i deployer-key ubuntu@${aws_instance.selenium-test.public_ip}"
}
