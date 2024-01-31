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
  name    = "env-${var.facts.environment}-eks-cluster"
  network = data.terraform_remote_state.network.outputs[var.facts.environment].workspaces_network[var.facts.workspace]
}

####################################################################################################
### Create cluster subnets
####################################################################################################
resource "aws_subnet" "cluster_a" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 7, 0)
  availability_zone = local.network.availability_zones["a"]

  tags = merge({Name = "${local.name}-a-subnet"}, var.facts)
}

resource "aws_subnet" "cluster_b" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 7, 1)
  availability_zone = local.network.availability_zones["b"]

  tags = merge({Name = "${local.name}-b-subnet"}, var.facts)
}

####################################################################################################
### Create EKS cluster IAM role
####################################################################################################
resource "aws_iam_role" "cluster" {
  name               = "EKSClusterRole${title(var.facts.environment)}"
  assume_role_policy = file("${path.module}/assets/cluster-role-trust-policy.json")

  tags = var.facts
}

resource "aws_iam_role_policy_attachment" "cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

####################################################################################################
### Create CloudWatch log group for control plane logging
####################################################################################################
resource "aws_cloudwatch_log_group" "this" {
  count             = var.enable_control_plane_logging == true ? 1 : 0
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = 30

  tags = var.facts
}

####################################################################################################
### Create Kubernetes cluster
####################################################################################################
resource "aws_eks_cluster" "this" {
  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.this
  ]

  name     = local.name
  role_arn = aws_iam_role.cluster.arn
  version  = "1.27"

  vpc_config {
    subnet_ids = [
      aws_subnet.cluster_a.id,
      aws_subnet.cluster_b.id
    ]

    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = var.enable_control_plane_logging == true ? ["api", "audit", "authenticator", "controllerManager", "scheduler"] : []
  tags = var.facts
}