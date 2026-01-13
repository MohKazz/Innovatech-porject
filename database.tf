# DB subnet group
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = [
  aws_subnet.db_a.id,
  aws_subnet.db_b.id,
  ]
  tags       = merge(var.tags, { Name = "${var.name}-db-subnets" })
}

# PostgreSQL instance
resource "aws_db_instance" "postgres" {
  identifier             = "${var.name}-pg"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true
  apply_immediately      = true
  deletion_protection    = false
  tags                   = merge(var.tags, { Name = "${var.name}-pg" })
}
# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "RDS inbound from app only"
  vpc_id      = aws_vpc.this.id
  tags = {
    Name = "rds-sg"
  }
}

resource "aws_security_group_rule" "rds_in_from_vpc" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.rds.id
}

resource "aws_security_group_rule" "rds_out_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # -1 means all protocols
  cidr_blocks       = ["0.0.0.0/0"] # allow all outbound traffic from any ip address
  security_group_id = aws_security_group.rds.id
}
