# VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.name}-vpc" })
}
 #IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

# Public subnets
resource "aws_subnet" "public" {
  for_each = {
    a = { az = var.azs[0], cidr = local.public_subnet_cidrs[0] }
    b = { az = var.azs[1], cidr = local.public_subnet_cidrs[1] }
  }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.name}-public-${each.key}", Tier = "public" })
}

# Private APP subnets
resource "aws_subnet" "app" {
  for_each = {
    a = { az = var.azs[0], cidr = local.app_subnet_cidrs[0] }
    b = { az = var.azs[1], cidr = local.app_subnet_cidrs[1] }
  }
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = merge(var.tags, { Name = "${var.name}-app-${each.key}", Tier = "app" })
}

# Private DB subnets
resource "aws_subnet" "db" {
  for_each = {
    a = { az = var.azs[0], cidr = local.db_subnet_cidrs[0] }
    b = { az = var.azs[1], cidr = local.db_subnet_cidrs[1] }
  }
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = merge(var.tags, { Name = "${var.name}-db-${each.key}", Tier = "db" })
}

# One NAT for all private subnets
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-eip" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["a"].id
  tags          = merge(var.tags, { Name = "${var.name}-nat" })
  depends_on    = [aws_internet_gateway.igw]
}

 
# ################ Route tables ##################

#first Public to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-rt-public" })
}

resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# second: private (app + db) to NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-rt-private" })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "app_assoc" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db_assoc" {
  for_each       = aws_subnet.db
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
