
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Generate RSA key pair
resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload public key to AWS in the configured region
resource "aws_key_pair" "deployer" {
  key_name   = "capstone-key"
  public_key = tls_private_key.deployer.public_key_openssh
}

# Write private key to local file
resource "local_file" "private_key" {
  content         = tls_private_key.deployer.private_key_pem
  filename        = "${path.module}/capstone.pem"
  file_permission = "0400"
}

module "vpc" {
  source     = "./modules/vpc"
  cidr_block = "192.168.0.0/26"
}

module "bastion" {
  source            = "./modules/bastion"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.subnets.public_subnet_ids
  key_name          = aws_key_pair.deployer.key_name
}

module "subnets" {
  source          = "./modules/subnets"
  vpc_id          = module.vpc.vpc_id
  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

module "routing" {
  source            = "./modules/routing"
  vpc_id            = module.vpc.vpc_id
  igw_id            = module.vpc.igw_id
  public_subnet_ids = module.subnets.public_subnet_ids
}

module "security" {
  source        = "./modules/security"
  vpc_id        = module.vpc.vpc_id
  bastion_sg_id = module.bastion.bastion_sg
}

module "alb" {
  source            = "./modules/alb"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.subnets.public_subnet_ids
  security_group_id = module.security.alb_sg_id
}

module "asg" {
  source            = "./modules/asg"
  public_subnet_ids = module.subnets.public_subnet_ids
  security_group_id = module.security.web_sg_id
  target_group_arn  = module.alb.target_group_arn
  key_name          = aws_key_pair.deployer.key_name
  db_endpoint       = module.rds.db_endpoint
  db_name           = module.rds.db_name
  db_username       = module.rds.db_username
  db_password       = var.db_password
  efs_dns_name      = module.efs.efs_dns_name
}

module "rds" {
  source            = "./modules/rds"
  subnet_ids        = module.subnets.private_subnet_ids
  security_group_id = module.security.db_sg_id
  db_name           = var.db_name
  username          = var.db_user
  password          = var.db_password
  depends_on        = [module.security]
}

module "efs" {
  source     = "./modules/efs"
  subnet_ids = module.subnets.public_subnet_ids
  efs_sg_id  = module.security.efs_sg_id
}

# Copy capstone.pem to the bastion after it boots
resource "null_resource" "copy_key_to_bastion" {
  depends_on = [module.bastion, local_file.private_key]

  connection {
    type        = "ssh"
    host        = module.bastion.public_ip
    user        = "ec2-user"
    private_key = tls_private_key.deployer.private_key_pem
    timeout     = "3m"
  }

  provisioner "file" {
    source      = local_file.private_key.filename
    destination = "/home/ec2-user/capstone.pem"
  }

  provisioner "remote-exec" {
    inline = ["chmod 400 /home/ec2-user/capstone.pem"]
  }
}

output "wordpress_url" {
  value = "http://${module.alb.wordpress_url}"
}

output "private_key_path" {
  value = local_file.private_key.filename
}

output "private_key_pem" {
  value     = tls_private_key.deployer.private_key_pem
  sensitive = true
}