#ALB across the public subnets. this is the load balancer that routes traffic to the web instances
resource "aws_lb" "web" {
  name               = "nca-alb"
  internal           = false # ensure the ALB is accessible from the Internet, if set to true it will be internal only
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets = [
  aws_subnet.public_a.id,
  aws_subnet.public_b.id,
  ]

}

#this listens on port 80 and then forwards traffic to the target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

#Attach the ASG to the target group
resource "aws_autoscaling_attachment" "web_tg" {
  autoscaling_group_name = aws_autoscaling_group.web.name
  lb_target_group_arn    = aws_lb_target_group.web.arn
}
# Target group for the web instances
resource "aws_lb_target_group" "web" {
  name        = "nca-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

}

# alb  Security Group
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "alb ingress on 80 from internet"
  vpc_id      = aws_vpc.this.id
}
# first rule for allowing inbound HTTP traffic from anywhere on port 80
resource "aws_security_group_rule" "alb_in_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] # allow from anywhere
  security_group_id = aws_security_group.alb.id
}
# second rule for allowing all outbound traffic
resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"] 
  security_group_id = aws_security_group.alb.id
}