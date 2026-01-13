# EC2 IAM Role and Instance Profile for SSM and CloudWatch
resource "aws_iam_role" "ec2" {
  name = "ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "ec2_cw_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}
resource "aws_iam_instance_profile" "ec2" {
  name = "ec2-profile"
  role = aws_iam_role.ec2.name
}

# AMI lookup for finding the latest Amazon Linux 2 instance
data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Launch Template
resource "aws_launch_template" "web" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ami.amazon_linux2.id # hardcoded image_id can aslo be used like this: image_id = "ami-0abcdef1234567890"
  instance_type = "t3.micro"

  iam_instance_profile { name = aws_iam_instance_profile.ec2.name }

  #This block assigns public IPs to web instances and attaches them to the a security group, in this case the web SG.
  network_interfaces { 
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
  }

 user_data = base64encode(<<-EOF
#!/bin/bash
set -eux
# Install Apache and Git
yum install -y httpd git
# Enable and start Apache
systemctl enable --now httpd
# Remove the default 403 welcome page
mv /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/welcome.conf.disabled || true
# Deploy my site form my GitHub repository
rm -rf /var/www/html/*
git clone https://github.com/MohKazz/Landing-Page.git /var/www/html
# Permissions for Apache
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
# Reload Apache
systemctl restart httpd
EOF
)
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-web" })
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "${var.name}-asg"
  desired_capacity          = 2
  min_size                  = 2
  max_size                  = 4
  vpc_zone_identifier = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id,
  ]
  health_check_type         = "EC2"
  health_check_grace_period = 60
  force_delete              = true

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-web"
    propagate_at_launch = true
  }
}
# 
resource "aws_autoscaling_policy" "web_cpu_target" { # target tracking policy
  name                      = "${var.name}-web-cpu-tt"
  autoscaling_group_name    = aws_autoscaling_group.web.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 60

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}

# Web Security Group
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "App instances behind ALB"
  vpc_id      = aws_vpc.this.id
  tags = {
    Name = "web-sg"
  }
}
# Allow the application load balancer to access the web App on port 80
resource "aws_security_group_rule" "web_in_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id # allow only traffic comming from the ALB security group
  security_group_id        = aws_security_group.web.id
}
# Allow all outbound traffic
resource "aws_security_group_rule" "web_out_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}