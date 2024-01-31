####################################################################################################
### Basic configuration
####################################################################################################

provider "aws" {
  region = "eu-central-1"
}

locals {
  facts = {
    organization = "org"
    workspace    = "sys_ecr"
    provisioner  = "terraform"
  }
}

####################################################################################################
### Create ECR private repositories
####################################################################################################
locals {
  ops-repos = [
    "psql"
  ]
}

resource "aws_ecr_repository" "this" {
  for_each             = toset(concat(local.ops-repos))
  name                 = each.value
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags                 = local.facts
}

output "ecr_repositories" {
  value = { for ecr_key, ecr in aws_ecr_repository.this : ecr_key => ecr.name }
}

####################################################################################################
### Create ECR public repositories
####################################################################################################

# Public ECR repositories can only be used in the us-east-1 region.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

locals {
  public-repos = [
    "frontend",
    "backend"
  ]
}
resource "aws_ecrpublic_repository" "this" {
  for_each             = toset(concat(local.public-repos))
  provider             = aws.us_east_1
  repository_name      = each.value
  tags                 = local.facts
}

output "ecr_public_repositories" {
  value = { for ecr_key, ecr in aws_ecrpublic_repository.this : ecr_key => ecr.repository_name }
}