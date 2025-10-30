# Application Load Balancer Security Group
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "ALB ingress on 80 from Internet"
  vpc_id      = aws_vpc.this.id
  tags = {
    Name = "alb-sg"
  }
}
resource "aws_security_group_rule" "alb_in_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}
resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}
# Web/App EC2 Security Group
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "App instances behind ALB"
  vpc_id      = aws_vpc.this.id
  tags = {
    Name = "web-sg"
  }
}
# Allow ALB to access App on port 80
resource "aws_security_group_rule" "web_in_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.web.id
}
resource "aws_security_group_rule" "web_out_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

# RDS Security Group (MySQL 3306 only from web SG)
resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "RDS inbound from app only"
  vpc_id      = aws_vpc.this.id
  tags = {
    Name = "rds-sg"
  }
}
# RDS Security Group (PostgreSQL 5432 only from web SG)
resource "aws_security_group_rule" "rds_in_from_web" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.web.id
  security_group_id        = aws_security_group.rds.id
}
resource "aws_security_group_rule" "rds_out_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
}

# EC2 IAM Role / Instance Profile (SSM + CW Read)
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
