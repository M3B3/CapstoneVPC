resource "aws_security_group" "alb" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_load_balancer"
  }

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web" {
  vpc_id = var.vpc_id

  tags = {
    Name = "aws_sg_web"
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  vpc_id = var.vpc_id


  tags = {
    Name = "aws_sg_database"
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
}

output "alb_sg" { value = aws_security_group.alb.id }
output "web_sg" { value = aws_security_group.web.id }
output "db_sg"  { value = aws_security_group.db.id }
