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
      name = "env_network"
    }
  }
}

locals {
  name    = "env-${var.facts.environment}-jumphost"
  network = data.terraform_remote_state.network.outputs[var.facts.environment].workspaces_network[var.facts.workspace]
}

####################################################################################################
### Create subnet and security group
####################################################################################################
resource "aws_subnet" "this" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 7, 0)
  availability_zone = local.network.availability_zones["a"]

  tags = merge({Name = "${local.name}-subnet"}, var.facts)
}

resource "aws_route_table_association" "this" {
  route_table_id = local.network.igw_route_table
  subnet_id      = aws_subnet.this.id
}

resource "aws_security_group" "this" {
  name   = "${local.name}-sg"
  vpc_id = local.network.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({Name = "${local.name}-sg"}, var.facts)
}

####################################################################################################
### Create EC2 instance
####################################################################################################
data "aws_ami" "this" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.this.image_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.this.id
  vpc_security_group_ids      = [aws_security_group.this.id]
  user_data                   = file("${path.module}/assets/setup.sh")

  volume_tags = merge({Name = "${local.name}-volume"}, var.facts)
  tags        = merge({
      Name = local.name,
      jumphost = true},
    var.facts)
}

resource "aws_eip" "this" {
  vpc      = true
  instance = aws_instance.this.id

  tags = merge({Name = "${local.name}-eip"}, var.facts)
}
