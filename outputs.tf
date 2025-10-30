# Core network
output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "private_app_subnet_ids" { value = [for s in aws_subnet.app : s.id] }
output "private_db_subnet_ids" { value = [for s in aws_subnet.db : s.id] }

# Security groups
output "alb_sg_id" { value = aws_security_group.alb.id }
output "web_sg_id" { value = aws_security_group.web.id }

# Database
output "rds_endpoint" { value = aws_db_instance.postgres.address }
