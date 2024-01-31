####################################################################################################
### Define common variables and get remote states
####################################################################################################
terraform {
  required_providers {
    aws = {source = "hashicorp/aws"}
  }
}

data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    organization = var.facts.organization
    workspaces = {
      name = "dev_network"
    }
  }
}

locals {
  name    = "env-${var.facts.environment}-rds-postgres"
  network = data.terraform_remote_state.network.outputs[var.facts.environment].workspaces_network[var.facts.workspace]
}

####################################################################################################
### Create database subnets, subnet group and security group
####################################################################################################
resource "aws_subnet" "db_a" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 7, 0)
  availability_zone = local.network.availability_zones["a"]

  tags = merge({Name = "${local.name}-a-subnet"}, var.facts)
}

resource "aws_route_table_association" "db_a" {
  route_table_id = local.network.igw_route_table
  subnet_id      = aws_subnet.db_a.id
}

resource "aws_subnet" "db_b" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 7, 1)
  availability_zone = local.network.availability_zones["b"]

  tags = merge({Name = "${local.name}-b-subnet"}, var.facts)
}

resource "aws_route_table_association" "db_b" {
  route_table_id = local.network.igw_route_table
  subnet_id      = aws_subnet.db_b.id
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-sng"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]

  tags = var.facts
}

data "aws_vpc" "this" {
  id = local.network.vpc_id
}

resource "aws_security_group" "this" {
  name   = "${local.name}-sg"
  vpc_id = local.network.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge({Name = "${local.name}-sg"}, var.facts)
}

####################################################################################################
### Create master password and store it in SSM
####################################################################################################
resource "random_password" "master_password"{
  length           = 16
  special          = true
  override_special = "_!%^"
}

resource "aws_ssm_parameter" "master_password" {
  name    = "${local.name}-master-password"
  type    = "SecureString"
  value   = random_password.master_password.result

  tags = var.facts
}

####################################################################################################
### Create database instance
####################################################################################################
resource "aws_db_instance" "this" {
  identifier                      = local.name
  engine                          = "postgres"
  engine_version                  = "15"
  instance_class                  = "db.t3.small"

  storage_type                    = "gp2"
  allocated_storage               = 10
  max_allocated_storage           = 20
  storage_encrypted               = true

  username                        = "postgres"
  password                        = aws_ssm_parameter.master_password.value

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  publicly_accessible             = true

  backup_retention_period         = 5
  deletion_protection             = true
  copy_tags_to_snapshot           = true

  tags                            = var.facts
}