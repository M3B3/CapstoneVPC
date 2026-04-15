resource "aws_db_subnet_group" "this" {
  subnet_ids = var.subnet_ids
}

resource "aws_db_instance" "this" {
  allocated_storage = 10
  engine            = "mysql"
  instance_class    = "db.t3.micro"

  db_name  = var.db_name
  username = var.username
  password = var.password

  multi_az = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]

  skip_final_snapshot = true

  tags = {
    Name = "rds_instance"
  }
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_username" {
  value = aws_db_instance.this.username
}