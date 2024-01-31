####################################################################################################
### Define common variables, assign /21 CIDR block for each specified workspace and get data
####################################################################################################
locals {
  availability_zones = ["a", "b", "c"]
  workspaces = [
    "dev_network",
    "dev_k8s-cluster-create",
    "dev_k8s-cluster-setup",
    "dev_ingress",
    "dev_jumphost",
    "dev_database"
  ]

  cidr_blocks = {
    for workspace in local.workspaces:
      workspace => cidrsubnet(aws_vpc.this.cidr_block, 5, index(local.workspaces, workspace))
  }

  name = "env-${var.facts.environment}-vpc"
}

data "aws_region" "this" {}

####################################################################################################
### Create VPC
####################################################################################################
resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge({Name = local.name}, var.facts)
}

####################################################################################################
### Create private route table and make it VPC main route table
####################################################################################################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge({Name = "${local.name}-private-rtb"}, var.facts)
}

resource "aws_main_route_table_association" "this" {
  route_table_id = aws_route_table.private.id
  vpc_id         = aws_vpc.this.id
}

####################################################################################################
### Create public route table with IGW
####################################################################################################
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags   = merge({Name = "${local.name}-igw"}, var.facts)
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge({Name = "${local.name}-public-rtb"}, var.facts)
}

####################################################################################################
### Create private route table with NAT gateway in each AZ
####################################################################################################
module "nat" {
  source = "./modules/nat"

  for_each = toset(local.availability_zones)

  vpc_id            = aws_vpc.this.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(local.cidr_blocks[var.facts.workspace], 7, index(local.availability_zones, each.value))
  region            = data.aws_region.this.name
  route_table_id    = aws_route_table.public.id

  vpc_peering_routes = {}

  facts = var.facts
}