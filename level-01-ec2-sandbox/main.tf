# 1. Define the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2" # Change this if you prefer a different region close to you
}

# Dynamically find the latest official Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
    most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical's official AWS Account ID
}

# 2. Create a Virtual Private Cloud (VPC)
resource "aws_vpc" "sandbox_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "sandbox-vpc"
  }
}

# 3. Create a Public Subnet
resource "aws_subnet" "sandbox_subnet" {
  vpc_id                  = aws_vpc.sandbox_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2a" # Must match your provider region
  tags = {
    Name = "sandbox-subnet"
  }
}

# 4. Create an Internet Gateway
resource "aws_internet_gateway" "sandbox_gw" {
  vpc_id = aws_vpc.sandbox_vpc.id
  tags = {
    Name = "sandbox-gw"
  }
}

# 5. Create and Associate Route Table
resource "aws_route_table" "sandbox_rt" {
  vpc_id = aws_vpc.sandbox_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sandbox_gw.id
  }
}

resource "aws_route_table_association" "sandbox_rta" {
  subnet_id      = aws_subnet.sandbox_subnet.id
  route_table_id = aws_route_table.sandbox_rt.id
}

# 6. Create Security Group (Firewall)
resource "aws_security_group" "sandbox_sg" {
  name        = "allow_web"
  description = "Allow inbound HTTP web traffic"
  vpc_id      = aws_vpc.sandbox_vpc.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For high security later, swap to your home's IP!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Register your local LXC public key with AWS
resource "aws_key_pair" "sandbox_ssh_key" {
  key_name   = "sandbox-lxc-key"
  public_key = file("~/.ssh/id_ed25519.pub") # Reads your public key file natively
}

# 7. Launch a Free-Tier EC2 Instance
resource "aws_instance" "sandbox_server" {
  ami           = data.aws_ami.ubuntu.id # pointer to data bloack at beginning of this file
  instance_type = "t3.micro"             # Covered entirely under Free Tier
  key_name      = aws_key_pair.sandbox_ssh_key.key_name

  subnet_id              = aws_subnet.sandbox_subnet.id
  vpc_security_group_ids = [aws_security_group.sandbox_sg.id]

  # Startup script runs automatically to pull down Nginx
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install nginx -y
              systemctl start nginx
              echo "<h1>Hello from your Native LXC Terraform Sandbox!</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "sandbox-ec2-instance"
  }
}

# 8. Output target address
output "instance_public_ip" {
  value       = aws_instance.sandbox_server.public_ip
  description = "The public IP address of the sandbox server."
}
