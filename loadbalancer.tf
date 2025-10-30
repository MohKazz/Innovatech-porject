
# Target group (forward to instances on 8080)
resource "aws_lb_target_group" "web" {
  name        = "${var.name}-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.this.id

  health_check {
    enabled             = true
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    path                = "/"
    port                = "traffic-port"   
    matcher             = "200"
  }
}


#ALB across the public subnets
resource "aws_lb" "web" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]
  tags               = merge(var.tags, { Name = "${var.name}-alb" })
}

#Listener on :80 -> forward to target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

#Let web instances accept traffic from the ALB on 8080
resource "aws_security_group_rule" "web_in_from_alb_8080" {
  type                     = "ingress"
  from_port                = 8080          
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id
  source_security_group_id = aws_security_group.alb.id
}

#Attach the ASG to the target group
resource "aws_autoscaling_attachment" "web_tg" {
  autoscaling_group_name = aws_autoscaling_group.web.name
  lb_target_group_arn    = aws_lb_target_group.web.arn
}

# outputs
output "alb_dns_name" { value = aws_lb.web.dns_name }
output "web_tg_arn"   { value = aws_lb_target_group.web.arn }
