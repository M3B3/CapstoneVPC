resource "aws_security_group" "alb_sg" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_load_balancer"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_sg" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_web"
  }

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description     = "SSH from Bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_database"
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
}

resource "aws_security_group" "efs_sg" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_efs"
  }

  ingress {
    description     = "NFS from web instances"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


output "efs_sg_id" { value = aws_security_group.efs_sg.id }
output "alb_sg_id" { value = aws_security_group.alb_sg.id }
output "web_sg_id" { value = aws_security_group.web_sg.id }
output "db_sg_id" { value = aws_security_group.db_sg.id }
