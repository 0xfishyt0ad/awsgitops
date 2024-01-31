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

data "aws_security_group" "cluster" {
  vpc_id = local.network.vpc_id
  name   = "eks-cluster-sg-*"
}

locals {
  name    = "env-${var.facts.environment}"
  network = data.terraform_remote_state.network.outputs[var.facts.environment].workspaces_network[var.facts.workspace]
}

####################################################################################################
### Create security groups for LBs created from Kubernetes LB Controller
####################################################################################################
resource "aws_security_group" "load_balancer_private" {
  name   = "${local.name}-kubernetes-lb-private-sg"
  vpc_id = local.network.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_link.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [data.aws_security_group.cluster.id]
  }

  tags = merge({Name = "${local.name}-kubernetes-lb-private-sg"}, var.facts)
}

resource "aws_security_group" "load_balancer_public" {
  name   = "${local.name}-kubernetes-lb-public-sg"
  vpc_id = local.network.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [data.aws_security_group.cluster.id]
  }

  tags = merge({Name = "${local.name}-kubernetes-lb-public-sg"}, var.facts)
}

####################################################################################################
### Create security group for VPC Link
####################################################################################################
resource "aws_security_group" "vpc_link" {
  name   = "${local.name}-apigateway-vpclink-sg"
  vpc_id = local.network.vpc_id

  tags = merge({Name = "${local.name}-apigateway-vpclink-sg"}, var.facts)
}

resource "aws_security_group_rule" "vpc_link_egress" {
  security_group_id        = aws_security_group.vpc_link.id
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.load_balancer_private.id
}

####################################################################################################
### Create rule in master cluster SG to allow traffic from LBs
####################################################################################################
resource "aws_security_group_rule" "cluster_sg_lb_private_ingress" {
  security_group_id        = data.aws_security_group.cluster.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.load_balancer_private.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "cluster_sg_lb_public_ingress" {
  security_group_id        = data.aws_security_group.cluster.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.load_balancer_public.id

  lifecycle {
    create_before_destroy = true
  }
}

####################################################################################################
### Create VPC Link and its subnets
####################################################################################################
resource "aws_subnet" "vpc_link_a" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 7, 0)
  availability_zone = local.network.availability_zones["a"]

  tags = merge({Name = "${local.name}-apigateway-vpclink-a-subnet"}, var.facts)
}

resource "aws_subnet" "vpc_link_b" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 7, 1)
  availability_zone = local.network.availability_zones["b"]

  tags = merge({Name = "${local.name}-apigateway-vpclink-b-subnet"}, var.facts)
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${local.name}-apigateway-vpclink"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = [aws_subnet.vpc_link_a.id, aws_subnet.vpc_link_b.id]

  tags               = var.facts
}

####################################################################################################
### Create Route 53 zone for ingress domain
####################################################################################################
resource "aws_route53_zone" "this" {
  name = "${var.facts.environment}.example.com"

  tags = var.facts
}

####################################################################################################
### Request SSL certificate
####################################################################################################
resource "aws_acm_certificate" "this" {
  domain_name               = aws_route53_zone.this.name
  subject_alternative_names = ["*.${aws_route53_zone.this.name}"]
  validation_method         = "DNS"

  tags = var.facts

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  name    = tolist(aws_acm_certificate.this.domain_validation_options)[0].resource_record_name
  records = [tolist(aws_acm_certificate.this.domain_validation_options)[0].resource_record_value]
  ttl     = 60
  type    = tolist(aws_acm_certificate.this.domain_validation_options)[0].resource_record_type
  zone_id = aws_route53_zone.this.zone_id
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn = aws_acm_certificate.this.arn
}

####################################################################################################
### Create CNAMEs for internet-facing LBs created from K8s LB Controller
####################################################################################################
#module "lb-cname" {
#  source = "./modules/lb-cname"
#
#  for_each = {for ingress in var.ingresses: ingress.hostname => ingress if ingress.kind == "lb"}
#
#  hostname = each.value.hostname
#  lb_name  = each.value.lb_name
#  zone_id  = aws_route53_zone.this.id
#}

#####################################################################################################
#### Create APIs
#####################################################################################################
#module "api-gateway" {
#  source = "./modules/api-gateway"
#
#  for_each = {for ingress in var.ingresses: ingress.hostname => ingress if ingress.kind == "api"}
#
#  domain          = aws_route53_zone.this.name
#  name            = each.value.hostname
#  lb_name         = each.value.lb_name
#  vpc_link_id     = aws_apigatewayv2_vpc_link.this.id
#  certificate_arn = aws_acm_certificate_validation.this.certificate_arn
#  zone_id         = aws_route53_zone.this.id
#
#  facts = var.facts
#}