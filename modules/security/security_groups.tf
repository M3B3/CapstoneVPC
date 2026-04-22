resource "aws_security_group" "alb_sg" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_load_balancer"
  }
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "web_sg" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_web"
  }
}

resource "aws_security_group_rule" "web_ingress_http_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.web_sg.id
  description              = "HTTP from ALB"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group_rule" "web_ingress_ssh_bastion" {
  type                     = "ingress"
  security_group_id        = aws_security_group.web_sg.id
  description              = "SSH from Bastion only"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = var.bastion_sg_id
}

resource "aws_security_group_rule" "web_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "db_sg" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_database"
  }
}

resource "aws_security_group_rule" "db_ingress_mysql_web" {
  type                     = "ingress"
  security_group_id        = aws_security_group.db_sg.id
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.web_sg.id
}

resource "aws_security_group" "efs_sg" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_efs"
  }
}

resource "aws_security_group_rule" "efs_ingress_nfs_web" {
  type                     = "ingress"
  security_group_id        = aws_security_group.efs_sg.id
  description              = "NFS from web instances"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.web_sg.id
}

resource "aws_security_group_rule" "efs_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.efs_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}


output "efs_sg_id" { value = aws_security_group.efs_sg.id }
output "alb_sg_id" { value = aws_security_group.alb_sg.id }
output "web_sg_id" { value = aws_security_group.web_sg.id }
output "db_sg_id" { value = aws_security_group.db_sg.id }
