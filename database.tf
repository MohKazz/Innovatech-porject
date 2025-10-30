# DB subnet group
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = [for s in aws_subnet.db : s.id]
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
