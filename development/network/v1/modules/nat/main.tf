####################################################################################################
### Define common variables
####################################################################################################
locals {
  name = "env-${var.facts.environment}-vpc-nat-${var.availability_zone}"
}

####################################################################################################
### Create VPC
####################################################################################################
resource "aws_subnet" "this" {
  vpc_id            = var.vpc_id
  cidr_block        = var.cidr_block
  availability_zone = "${var.region}${var.availability_zone}"

  tags = merge({Name = "${local.name}-subnet"}, var.facts)
}

resource "aws_route_table_association" "this" {
  route_table_id = var.route_table_id
  subnet_id      = aws_subnet.this.id
}

resource "aws_eip" "this" {
  domain = "vpc"

  tags = merge({Name = "${local.name}-eip"}, var.facts)
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.this.id
  subnet_id     = aws_subnet.this.id

  tags = merge({Name = local.name}, var.facts)
}

resource "aws_route_table" "this" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  dynamic "route" {
    for_each = var.vpc_peering_routes

    content {
      cidr_block                = route.value["cidr_block"]
      vpc_peering_connection_id = route.value["vpc_peering_connection_id"]
    }
  }

  tags   = merge({Name = "${local.name}-rtb"}, var.facts)
}

