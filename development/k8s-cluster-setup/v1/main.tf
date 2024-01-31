####################################################################################################
### Define common variables and get remote states
####################################################################################################
terraform {
  required_providers {
    aws              = {source = "hashicorp/aws"}
    kubernetes       = {source = "hashicorp/kubernetes"}
    helm             = {source = "hashicorp/helm"}
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

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

locals {
  name        = var.cluster_name
  network     = data.terraform_remote_state.network.outputs[var.facts.environment].workspaces_network[var.facts.workspace]
}

####################################################################################################
### Create developers Role using RBAC
####################################################################################################
resource "kubernetes_cluster_role" "iam_roles_developers" {
  metadata {
    name = "org:developers"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["*"]
    resources  = ["pods", "pods/portforward", "pods/exec", "deployments/scale"]
    verbs      = ["*"]
  }
}

####################################################################################################
### Bind Role with developers Group
####################################################################################################
resource "kubernetes_cluster_role_binding" "iam_roles_developers" {
  metadata {
    name = "org:developers"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "org:developers"
  }

  subject {
    kind = "Group"
    name = "org:developers"
    api_group = "rbac.authorization.k8s.io"
  }
}

####################################################################################################
### Create ConfigMap aws-auth
####################################################################################################
data "aws_iam_group" "admins" {
  group_name = "Administrators"
}

data "aws_iam_group" "developers" {
  group_name = "Developers"
}

data "aws_caller_identity" "this" {}

locals {
  configmap_admin_users = [
    for admin in data.aws_iam_group.admins.users :
    {
      userarn  = admin.arn
      username = admin.user_name
      groups   = ["system:masters"]
    }
  ]

  configmap_developer_users = [
    for developer in data.aws_iam_group.developers.users :
    {
      userarn  = developer.arn
      username = developer.user_name
      groups   = ["org:developers"]
    }
  ]

  configmap_users = concat(local.configmap_admin_users, local.configmap_developer_users)

  configmap_roles = [
    {
      rolearn  = aws_iam_role.fargate.arn
      username = "system:node:{{SessionName}}"
      groups   = ["system:bootstrappers", "system:nodes", "system:node-proxier"]
    }
  ]
}

resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(local.configmap_roles)
    mapUsers = yamlencode(local.configmap_users)
  }
}

####################################################################################################
### Create Fargate subnets and associate them with NAT route table
####################################################################################################
resource "aws_subnet" "fargate_a" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 3, 1)
  availability_zone = local.network.availability_zones["a"]

  tags = merge({Name = "${local.name}-fargate-a-subnet"}, var.facts)
}

resource "aws_subnet" "fargate_b" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 3, 2)
  availability_zone = local.network.availability_zones["b"]

  tags = merge({Name = "${local.name}-fargate-b-subnet"}, var.facts)
}

resource "aws_route_table_association" "fargate_a" {
  route_table_id = local.network.nat_route_tables["a"]
  subnet_id      = aws_subnet.fargate_a.id
}

resource "aws_route_table_association" "fargate_b" {
  route_table_id = local.network.nat_route_tables["b"]
  subnet_id      = aws_subnet.fargate_b.id
}

####################################################################################################
### Create Fargate profile IAM role
####################################################################################################
resource "aws_iam_role" "fargate" {
  name               = "EKSFargatePodExecutionRole${title(var.facts.environment)}"
  assume_role_policy = file("${path.module}/assets/pod-execution-role-trust-policy.json")

  tags = var.facts
}

resource "aws_iam_role_policy_attachment" "fargate" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate.name
}

####################################################################################################
### Create namespaces and Fargate profile for each including existing namespace kube-system
####################################################################################################
locals {
  namespaces = [
    "backend",
    "argocd",
    "aws-observability",
    "sonarqube",
    "frontend"
  ]
}

resource "aws_eks_fargate_profile" "this" {
  depends_on = [
    aws_iam_role_policy_attachment.fargate,
    kubernetes_config_map.aws_auth
  ]

  for_each   = toset(concat(local.namespaces, ["kube-system"]))

  cluster_name           = data.aws_eks_cluster.this.name
  fargate_profile_name   = "${local.name}-${each.value}-fp"
  pod_execution_role_arn = aws_iam_role.fargate.arn

  subnet_ids = [
    aws_subnet.fargate_a.id,
    aws_subnet.fargate_b.id
  ]

  selector {
    namespace = each.value
  }

  tags = var.facts
}

resource "kubernetes_namespace" "this" {
  depends_on = [aws_eks_fargate_profile.this]
  for_each   = toset(local.namespaces)

  metadata {
    name = each.value
  }
}

####################################################################################################
### Patch CoreDNS deployment to run on Fargate
####################################################################################################
data aws_eks_cluster_auth "this" {
  name = data.aws_eks_cluster.this.name
}

resource "null_resource" "patch_coredns_deployment" {
  depends_on = [aws_eks_fargate_profile.this]

  provisioner "local-exec" {
    command = <<EOH
cat >/tmp/ca.crt <<EOF
${base64decode(data.aws_eks_cluster.this.certificate_authority.0.data)}
EOF
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x ./kubectl && \
./kubectl \
  --server="${data.aws_eks_cluster.this.endpoint}" \
  --certificate-authority=/tmp/ca.crt \
  --token="${data.aws_eks_cluster_auth.this.token}" \
  patch deployment coredns \
  -n kube-system --type json \
  -p='[{"op": "remove", "path": "/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'
EOH
  }
}

####################################################################################################
### Enable logging to CloudWatch
####################################################################################################
resource "aws_iam_policy" "aws_logging" {
  name    = "AWSFargateCloudWatchLoggingIAMPolicy${title(var.facts.environment)}"
  policy  = file("${path.module}/assets/cloudwatch-logging-policy.json")

  tags    = var.facts
}

resource "aws_iam_role_policy_attachment" "aws_logging" {
  role       = aws_iam_role.fargate.name
  policy_arn = aws_iam_policy.aws_logging.arn
}

resource "kubernetes_config_map" "aws_logging" {
  depends_on = [
    kubernetes_namespace.this
  ]

  metadata {
    name      = "aws-logging"
    namespace = "aws-observability"
  }

  data = {
    "output.conf" = templatefile("${path.module}/assets/cloudwatch-logging-config-output.tpl", {
      region        = data.aws_region.this.name
      cluster_name  = var.cluster_name
    })
    "parsers.conf" = file("${path.module}/assets/cloudwatch-logging-config-parsers.conf")
    "filters.conf" = file("${path.module}/assets/cloudwatch-logging-config-filters.conf")
  }
}

####################################################################################################
### Create an IAM OIDC provider for cluster
####################################################################################################
resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
  url             = data.aws_eks_cluster.this.identity.0.oidc.0.issuer

  tags = var.facts
}

####################################################################################################
### Create IAM policy and role for load balancer controller
####################################################################################################
resource "aws_iam_policy" "lb_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy${title(var.facts.environment)}"
  policy = file("${path.module}/assets/load-balancer-controller-policy.json")

  tags = var.facts
}

resource "aws_iam_role" "lb_controller" {
  name               = "EKSLoadBalancerControllerRole${title(var.facts.environment)}"
  assume_role_policy = templatefile("${path.module}/assets/load-balancer-controller-role-trust-policy.json",
    {
      iam_oidc_provider_arn = aws_iam_openid_connect_provider.this.arn
      iam_oidc_provider_url = aws_iam_openid_connect_provider.this.url
    })

  tags = var.facts
}

resource "aws_iam_role_policy_attachment" "lb" {
  policy_arn = aws_iam_policy.lb_controller.arn
  role       = aws_iam_role.lb_controller.name
}

####################################################################################################
### Create service account and install load balancer controller
####################################################################################################
resource "kubernetes_service_account" "lb_controller" {
  metadata {
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }

    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn": aws_iam_role.lb_controller.arn
    }
  }
}

resource "kubernetes_manifest" "lb_controller_ic_crds" {
  manifest = yamldecode(file("${path.module}/assets/load-balancer-controller-ic-crds.yaml"))
}

resource "kubernetes_manifest" "lb_controller_tgb_crds" {
  manifest = yamldecode(file("${path.module}/assets/load-balancer-controller-tgb-crds.yaml"))
}

data "aws_region" "this" {}

resource "helm_release" "lb_controller" {
  depends_on = [
    kubernetes_manifest.lb_controller_tgb_crds,
    kubernetes_manifest.lb_controller_ic_crds,
    kubernetes_service_account.lb_controller,
    aws_eks_fargate_profile.this
  ]

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.5.4"
  namespace  = "kube-system"

  set {
    name = "clusterName"
    value = data.aws_eks_cluster.this.name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "vpcId"
    value = local.network.vpc_id
  }

  set {
    name  = "region"
    value = data.aws_region.this.name
  }

  # disable HA for development environment
  set {
    name  = "replicaCount"
    value = 1
  }
}

####################################################################################################
### Create pairs of private and public subnets for LBs
####################################################################################################
locals {
  lb_subnet_tags = {
    private = {
      "kubernetes.io/cluster/${data.aws_eks_cluster.this.name}" = "owned"
      "kubernetes.io/role/internal-elb"                         = 1
    }

    public = {
      "kubernetes.io/cluster/${data.aws_eks_cluster.this.name}" = "owned"
      "kubernetes.io/role/elb"                                  = 1
    }
  }
}

resource "aws_subnet" "lb_private_a" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 6, 0)
  availability_zone = local.network.availability_zones["a"]

  tags = merge({Name = "${local.name}-lb-private-a-subnet"}, local.lb_subnet_tags.private, var.facts)
}

resource "aws_subnet" "lb_private_b" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 6, 1)
  availability_zone = local.network.availability_zones["b"]

  tags = merge({Name = "${local.name}-lb-private-b-subnet"}, local.lb_subnet_tags.private, var.facts)
}

resource "aws_subnet" "lb_public_a" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 6, 2)
  availability_zone = local.network.availability_zones["a"]

  tags = merge({Name = "${local.name}-lb-public-a-subnet"}, local.lb_subnet_tags.public, var.facts)
}

resource "aws_subnet" "lb_public_b" {
  vpc_id            = local.network.vpc_id
  cidr_block        = cidrsubnet(local.network.cidr_block, 6, 3)
  availability_zone = local.network.availability_zones["b"]

  tags = merge({Name = "${local.name}-lb-public-b-subnet"}, local.lb_subnet_tags.public, var.facts)
}

resource "aws_route_table_association" "lb_public_a" {
  route_table_id = local.network.igw_route_table
  subnet_id      = aws_subnet.lb_public_a.id
}

resource "aws_route_table_association" "lb_public_b" {
  route_table_id = local.network.igw_route_table
  subnet_id      = aws_subnet.lb_public_b.id
}

####################################################################################################
### Create IAM OIDC provider for GitLab
####################################################################################################

resource "aws_iam_openid_connect_provider" "gitlab_oidc" {
  url             = "https://gitlab.creativedock.cloud"
  client_id_list  = ["https://gitlab.creativedock.cloud"]
  thumbprint_list = ["1d95521fbb80374c0a75c6c23dda33148a09d4ba"]
  
  tags = var.facts
}

####################################################################################################
### Create Assume Role Policy
####################################################################################################

resource "aws_iam_role" "gitlab_ci" {
  name               = "AssumeRoleForGitLab${title(var.facts.environment)}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Federated": "${aws_iam_openid_connect_provider.gitlab_oidc.arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "${aws_iam_openid_connect_provider.gitlab_oidc.url}:sub": "project_path:org/*:ref_type:branch:ref:*"
        }
      }
    }
  ]
}
EOF

  tags = var.facts
}

####################################################################################################
### Create Policy for AWS ECR Access with Full Permissions
####################################################################################################

resource "aws_iam_policy" "gitlab_ci" {
  name        = "ECRFullAccessPolicy${title(var.facts.environment)}"
  description = "Provides full access to AWS ECR"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecr:*",
      "Resource": "*"
    }
  ]
}
EOF

  tags = var.facts
}

####################################################################################################
### Attach Policies to the Assume Role
####################################################################################################

resource "aws_iam_role_policy_attachment" "assume_role_ecr" {
  role       = aws_iam_role.gitlab_ci.name
  policy_arn = aws_iam_policy.gitlab_ci.arn
}

####################################################################################################
### Install Argo CD
####################################################################################################
resource "kubernetes_secret" "argocd_repository_secret" {
  depends_on = [kubernetes_namespace.this]

  metadata {
    name      = "argocd-repository-credentials"
    namespace = "argocd"
  }

  data = {
    git-ssh-key = base64decode(var.argocd_git_ssh_key)
  }
}

locals {
  argocd_values = {
    environment = var.facts.environment
  }
}

#
resource "helm_release" "argo_cd" {
  depends_on = [
    kubernetes_namespace.this,
    kubernetes_secret.argocd_repository_secret,
    helm_release.lb_controller
  ]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm/"
  chart      = "argo-cd"
  namespace  = "argocd"
  version    = "5.34.6"
  values     = [templatefile("${path.module}/assets/helm/argocd.yaml", local.argocd_values)]

  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = var.argocd_admin_password_hash
  }
}

#####################################################################################################
#### Install storage class for EFS
#####################################################################################################
#resource "kubernetes_storage_class_v1" "storage_class_efs" {
#  metadata {
#    name = "efs-sc"
#  }
#  storage_provisioner = "efs.csi.aws.com"
#}
