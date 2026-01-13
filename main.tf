#This file contains the provider setup and the VPC, subnets, internet gateway, NAT gateway, route tables and routes.

# provider and terraform setup
provider "aws" {
  region = var.region
}

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "cs1nca-tfstate-131464424832-eu-central-1"
    key            = "cs1/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "cs1nca-tflock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    #kubernetes provider for managing k8s resources
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

# VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
}

# Subnet CIDRs
locals {
  public_subnet_cidrs = [
    "10.20.0.0/20",
    "10.20.16.0/20",
  ]
  app_subnet_cidrs = [
    "10.20.32.0/20",
    "10.20.48.0/20",
  ]
  db_subnet_cidrs = [
    "10.20.64.0/20",
    "10.20.80.0/20",
  ]
}

# Public subnets
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[0]
  availability_zone       = var.azs[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[1]
  availability_zone       = var.azs[1]
  map_public_ip_on_launch = true
}

# Private APP subnets 
resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app_subnet_cidrs[0]
  availability_zone = var.azs[0]
}

resource "aws_subnet" "app_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app_subnet_cidrs[1]
  availability_zone = var.azs[1]
}

# Private DB subnets 
resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.db_subnet_cidrs[0]
  availability_zone = var.azs[0]
}

resource "aws_subnet" "db_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.db_subnet_cidrs[1]
  availability_zone = var.azs[1]
}

# One NAT for all private subnets
resource "aws_eip" "nat" {
  domain = "vpc"
}

# Outputs
output "nat_eip_public_ip" { value = aws_eip.nat.public_ip }

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
}

# Routes and route tables
# Public to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate public subnet a
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
# Associate public subnet b
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Private route tables and routes
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
}
# route to nat
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

# Associate private subnets for app and db
resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db_a" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db_b" {
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.private.id
}


