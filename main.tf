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
  public_key = file("deployer-key.pub")
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

resource "aws_instance" "selenium-test" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.deployer.key_name
  tags = {
    Name = "SeleniumTestInstance"
  }
}
