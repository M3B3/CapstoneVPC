
provider "aws" {
  region = var.region
}

module "vpc" {
  source     = "./modules/vpc"
  cidr_block = "192.168.0.0/26"
}

module "bastion" {
  source            = "./modules/bastion"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.subnets.public_subnet_ids
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
  key_name          = var.key_name
  db_endpoint       = module.rds.db_endpoint
  db_name           = module.rds.db_name
  db_username       = module.rds.db_username
  db_password       = var.db_password
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
