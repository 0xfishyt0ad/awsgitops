####################################################################################################
### Define common variables and get remote states
####################################################################################################
terraform {
  required_providers {
    aws              = {source = "hashicorp/aws"}
    kubernetes       = {source = "hashicorp/kubernetes"}
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
  network = data.terraform_remote_state.network.outputs[var.facts.environment].workspaces_network[var.facts.workspace]
}

data "aws_security_group" "cluster" {
  vpc_id = local.network.vpc_id
  name   = "eks-cluster-sg-${var.cluster_name}-*"
}

resource "aws_efs_file_system" "this" {
  creation_token   = "env-${var.facts.environment}-${var.cluster_name}-${var.application_name}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  tags = merge({
    Name = "env-${var.facts.environment}-${var.cluster_name}-${var.application_name}-efs"
  }, var.facts)
}

resource "aws_efs_mount_target" "this" {
  for_each        = var.subnets
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [data.aws_security_group.cluster.id]
}

resource "kubernetes_persistent_volume" "this" {
  metadata {
    name   = "${var.application_name}-efs-pv"
    labels = {
      "app" = var.application_name
    }
  }
  spec {
    capacity = {
      storage = var.volume_size
    }
    access_modes                      = ["ReadWriteMany"]
    persistent_volume_reclaim_policy  = "Retain"
    storage_class_name                = "efs-sc"
    persistent_volume_source {
      csi {
        driver        = "efs.csi.aws.com"
        volume_handle = aws_efs_file_system.this.id
      }
    }
  }
}