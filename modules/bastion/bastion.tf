resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  subnet_id                   = var.public_subnet_ids[0]
  associate_public_ip_address = true
  key_name                    = var.key_name

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "bastion-host"
  }
}


resource "aws_security_group" "bastion_sg" {
  vpc_id = var.vpc_id

  tags = {
    Name = "bastion-sg"
  }

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  // ToDo obtain ip dynamically
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

output "bastion_sg"  { value = aws_security_group.bastion_sg.id }
output "public_ip"   { value = aws_instance.bastion.public_ip }