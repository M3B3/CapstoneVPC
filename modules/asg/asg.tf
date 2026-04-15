resource "aws_launch_template" "lt" {
  name_prefix = "capstone-wordpress-"
  image_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.al2023.value
  instance_type = "t3.micro"
  key_name = var.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.security_group_id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "capstone-ec2-instance"
    }
  }
  user_data = base64encode(templatefile("${path.root}/modules/scripts/user_data.sh", {
    db_endpoint = var.db_endpoint
    db_name     = var.db_name
    db_user     = var.db_username
    db_password = var.db_password
  }))
}

resource "aws_autoscaling_group" "asg" {
  desired_capacity = 2
  max_size         = 3
  min_size         = 2

  vpc_zone_identifier = var.public_subnet_ids

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  target_group_arns = [var.target_group_arn]
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}