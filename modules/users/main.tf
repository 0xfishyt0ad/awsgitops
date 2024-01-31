####################################################################################################
### Basic configuration
####################################################################################################

provider "aws" {
  region = "eu-central-1"
}

locals {
  facts = {
    organization = "org"
    workspace    = "sys_users"
    provisioner  = "terraform"
  }
}

####################################################################################################
### Create custom and register managed policies
####################################################################################################
locals {
  policies = {
    iam_allow_own_credentials_no_mfa = {
      name = "IAMAllowOwnCredentialsNoMFA"
      type = "custom"
    }

    administrator_access = {
      name = "AdministratorAccess"
      type = "managed"
    }

    read_only_access = {
      name = "ReadOnlyAccess"
      type = "managed"
    }

    billing = {
      name = "job-function/Billing"
      type = "managed"
    }

    ec2_instance_connect_jumphost = {
      name = "EC2InstanceConnectJumphost"
      type = "custom"
    }

    cloudwatch_dashboards_management = {
      name = "CloudWatchDashboardsManagement"
      type = "custom"
    }

    cloudwatch_logs_query_definitions_management = {
      name = "CloudWatchLogsQueryDefinitionsManagement"
      type = "custom"
    }
  }
}

resource "aws_iam_policy" "this" {
  for_each = {for policy_key, policy in local.policies: policy_key => policy if policy.type == "custom"}

  name   = each.value.name
  policy = file("${path.module}/assets/${each.key}.json")

  tags   = local.facts
}

####################################################################################################
### Create groups and attach policies to them
####################################################################################################
data "aws_caller_identity" "this" {}

locals {
  groups = {
    administrators = {
      name     = "Administrators"
      policies = [
        local.policies.administrator_access
      ]
    }

    billing = {
      name     = "Billing"
      policies = [
        local.policies.billing,
        local.policies.iam_allow_own_credentials_no_mfa
      ]
    }

    developers = {
      name     = "Developers"
      policies = [
        local.policies.read_only_access,
        local.policies.iam_allow_own_credentials_no_mfa,
        local.policies.ec2_instance_connect_jumphost,
        local.policies.cloudwatch_dashboards_management,
        local.policies.cloudwatch_logs_query_definitions_management
      ]
    }
  }

  policy_arn_prefixes = {
    managed = "arn:aws:iam::aws:policy/"
    custom  = "arn:aws:iam::${data.aws_caller_identity.this.account_id}:policy/"
  }

  group_policies = flatten([
    for group_key, group in local.groups: [
      for policy in group.policies: {
        group_name = group.name
        policy_arn = "${local.policy_arn_prefixes[policy.type]}${policy.name}"
      }
    ]
  ])
}

resource "aws_iam_group" "this" {
  for_each = local.groups

  name     = each.value.name
}

resource "aws_iam_group_policy_attachment" "this" {
  depends_on = [aws_iam_group.this, aws_iam_policy.this]

  for_each   = {for policy in local.group_policies: "${policy.group_name}.${policy.policy_arn}" => policy}

  group      = each.value.group_name
  policy_arn = each.value.policy_arn
}

####################################################################################################
### Create users and attach groups to them
####################################################################################################
locals {
  users = {
    john_doe = {
      name   = "john.doe"
      groups = [
        local.groups.administrators,
        local.groups.billing
      ]
    },
    
    jane_doe = {
      name   = "jane.doe"
      groups = [
        local.groups.developers,
      ]
    },
  }
}

resource "aws_iam_user" "this" {
  for_each = local.users

  name     = each.value.name
  path     = "/people/"

  tags     = local.facts
}

resource "aws_iam_user_group_membership" "this" {
  depends_on = [aws_iam_user.this, aws_iam_group.this]

  for_each = local.users

  user     = each.value.name
  groups   = each.value.groups[*].name
}

output "users" {
  value = { for user_key, user in aws_iam_user.this : user_key => user.name }
}

output "policies" {
  value = { for policy_key, policy in aws_iam_policy.this : policy_key => policy.name }
}

output "groups" {
  value = { for group_key, group in aws_iam_group.this : group_key => group.name }
}

output "user_group_membership" {
  value = { for user_key, user in aws_iam_user_group_membership.this : user_key => user.groups }
}

output "policy_group_attachment" {
  value = { for policy_key, policy_attachment in aws_iam_group_policy_attachment.this : policy_key => policy_attachment.policy_arn }
}
