##############################################################################
# providers.tf
# IBM Cloud provider configuration
# Equivalent to: no direct CFN equivalent (provider setup is implicit in AWS)
##############################################################################

terraform {
  required_version = ">= 1.3"
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">= 1.65"
    }
  }
}

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
}

##############################################################################
# Data sources
##############################################################################

data "ibm_resource_group" "rg" {
  name = var.resource_group_name
}

# Retrieve the list of zones in the chosen region
data "ibm_is_zones" "regional" {
  region = var.region
}

locals {
  # Limit zones to the number requested
  zones = slice(data.ibm_is_zones.regional.zones, 0, var.number_of_zones)

  common_tags = ["${var.tag_name}:${var.tag_value}"]
}
