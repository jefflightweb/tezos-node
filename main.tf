
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

variable "project" {
  type        = string
  description = "The name of the project"
  default     = "tz"
  validation {
    # regex(...) fails if it cannot find a match
    condition     = can(regex("[a-z]+", var.project))
    error_message = "The project name must only include lower case letters."
  }
}

variable "size" {
  type        = string
  description = "The EC2 instance size"
  default     = "c5a.large"
}

variable "block" {
  type = string
  description = "Latest Tezos rolling snapshot block hash - see: https://xtz-shots.io/mainnet/"
}

variable "public_key_file" {
  type = string
  description = "Path to SSH public key file"
}

data "local_file" "ssh_public_key" {
  filename = var.public_key_file
}

provider "aws" {
  profile = "default"
  region  = "us-east-2"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "ec2-${lower(var.project)}-tz"
  public_key = data.local_file.ssh_public_key.content
#  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDFYH+R2Dbr7a/d7dD535fEgxS6AK6JLg7kIm4l1XSx0qWrGqhAVCRAE+GDqscgeUIDqWPRJaqqeFyEnn1O7vppEVlGITYVb9Jjy1OsFPrAXUOvp71l7V6cd8lEqAASOIQjjYA6vYY+WobC9tf13D2cPPpqK4bkzmAslnFPl9RecQrfVMiqKbHHpEKa1QCvlktL3gLBo2/o7BdjTLTzVKYAKD8O1bJ3kkRtuvx7lZJpcFnP8uabZxUOXv7AYt/Hle3N2Hk6CAqR6a14FEePdVVQfI4yUiDlBYYSgOGio9BIukBqbgQ5b0dA7EMvU5hmCq8YI5tzT4VWEMDH99lyFDNr lightweb"
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_default_vpc.default.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  ingress {
    protocol = "TCP"
    from_port = 22
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_s3_access_role" {
  name               = "${upper(var.project)}-single-s3-role"
  assume_role_policy = file("assumerolepolicy.json")
}

resource "aws_iam_policy" "policy" {
  name        = "EC2-${upper(var.project)}-single-policy"
  description = "EC2-${upper(var.project)} policy"
  policy      = templatefile("policys3bucket.json.tmpl", 
    { project = var.project }
  )
}

resource "aws_iam_policy_attachment" "attach" {
  name       = "policy-attachment"
  roles      = ["${aws_iam_role.ec2_s3_access_role.name}"]
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_iam_instance_profile" "profile" {
  name = "EC2-${upper(var.project)}-single-profile"
  role = aws_iam_role.ec2_s3_access_role.name
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_default_vpc.default.id
  service_name = "com.amazonaws.us-east-2.s3"
}

resource "aws_kms_key" "root_key" {
  description = "Root EBS KMS key"
  deletion_window_in_days = 10
}

resource "aws_instance" "processor" {
  ami = data.aws_ami.ubuntu.id
  instance_type        = var.size
  user_data            = templatefile("${path.module}/ec2_userdata_${var.project}.tmpl", {
                             project = var.project, block = var.block
                          })
  key_name             = aws_key_pair.ec2_key.key_name
  vpc_security_group_ids = [ aws_default_security_group.default.id ]
  iam_instance_profile = aws_iam_instance_profile.profile.name
  ebs_optimized        = true
  root_block_device {
    encrypted = true
    kms_key_id = aws_kms_key.root_key.id
    volume_size = 500
  }

  tags = {
    Name    = "EC2_${upper(var.project)}"
    Project = "${upper(var.project)}"
  }
  volume_tags = {
    Name    = "EC2_${upper(var.project)}_Vol"
    Project = "${upper(var.project)}"
  }
}

output "ec2_global_ips" {
  value = ["${aws_instance.processor.*.public_ip}"]
}
