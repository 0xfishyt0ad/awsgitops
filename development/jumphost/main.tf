####################################################################################################
### Basic configuration
####################################################################################################
provider "aws" {
  region = "eu-central-1"
}

locals {
  facts = {
    organization = "org"
    workspace    = "env_jumphost"
    provisioner  = "terraform"
  }
}

####################################################################################################
### Create jumphost for each environment
####################################################################################################
module "dev" {
  source = "./v1"

  facts = merge({environment = "dev"}, local.facts)
}
