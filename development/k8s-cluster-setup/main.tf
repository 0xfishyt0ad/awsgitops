####################################################################################################
### Basic configuration
####################################################################################################
provider "aws" {
  region = "eu-central-1"
}

locals {
  facts = {
    organization = "org"
    workspace    = "dev_k8s-cluster-setup"
    provisioner  = "terraform"
    environment  = "dev"
  }
}

data "terraform_remote_state" "k8s-cluster-create" {
  backend = "remote"
  config = {
    organization = local.facts.organization
    workspaces = {
      name = "dev_k8s-cluster-create"
    }
  }
}

####################################################################################################
### Setup Kubernetes cluster for current environment
####################################################################################################
data "aws_eks_cluster" "dev" {
  name = data.terraform_remote_state.k8s-cluster-create.outputs.dev.cluster_name
}

data "aws_eks_cluster_auth" "dev" {
  name = data.aws_eks_cluster.dev.name
}

provider "kubernetes" {
  alias                  = "dev"
  host                   = data.aws_eks_cluster.dev.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.dev.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.dev.token
}

provider "helm" {
  alias = "dev"

  kubernetes {
    host                   = data.aws_eks_cluster.dev.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.dev.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.dev.token
  }
}

module "dev" {
  source    = "./v1"
  providers = {
    kubernetes       = kubernetes.dev
    helm             = helm.dev
  }

  cluster_name = data.aws_eks_cluster.dev.name

  argocd_admin_password_hash = var.argocd_admin_password_hash
  argocd_git_ssh_key         = var.argocd_git_ssh_key

  facts                      = local.facts
}

output "dev" {
  value = module.dev
  description = "Cluster outputs of current environment"
}

#module "dev-efs" {
#  source    = "./modules/efs"
#  providers = {
#    kubernetes     = kubernetes.dev
#  }
#
#  for_each = {
#    sonarqube = { application_name = "sonarqube", volume_size = "5Gi" }
#    metada    = { application_name = "metada", volume_size = "5Gi" }
#  }
#
#  cluster_name = data.aws_eks_cluster.dev.name
#  subnets = {
#    subnet_a = module.dev.cluster_subnet_a_id,
#    subnet_b = module.dev.cluster_subnet_b_id,
#  }
#
#  application_name = each.value.application_name
#  volume_size      = each.value.volume_size
#
#  facts =  merge({environment = "dev"}, local.facts)
#}
