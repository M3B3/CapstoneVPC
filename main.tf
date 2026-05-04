
terraform {
  cloud {
    organization = "M3B3_org"
    workspaces {
      name = "CapstoneVPC"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = "capstone-key"
  public_key = tls_private_key.deployer.public_key_openssh
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
  alb_dns_name      = module.alb.wordpress_url
  wp_admin_user     = var.wp_admin_user
  wp_admin_password = var.wp_admin_password
  wp_admin_email    = var.wp_admin_email
  wp_site_title     = var.wp_site_title
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
  depends_on = [module.bastion]

  connection {
    type        = "ssh"
    host        = module.bastion.public_ip
    user        = "ec2-user"
    private_key = tls_private_key.deployer.private_key_pem
    timeout     = "3m"
  }

  provisioner "file" {
    content     = tls_private_key.deployer.private_key_pem
    destination = "/home/ec2-user/capstone.pem"
  }

  provisioner "remote-exec" {
    inline = ["chmod 400 /home/ec2-user/capstone.pem"]
  }
}

output "wordpress_url" {
  value = "http://${module.alb.wordpress_url}"
}

output "bastion_private_key" {
  value     = tls_private_key.deployer.private_key_pem
  sensitive = true
}

output "bastion_public_ip" {
  value = module.bastion.public_ip
}