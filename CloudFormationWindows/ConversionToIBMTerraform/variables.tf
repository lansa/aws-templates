##############################################################################
# variables.tf
# Shared input variables for the IBM Cloud LANSA stack
##############################################################################

variable "ibmcloud_api_key" {
  description = "IBM Cloud API key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "IBM Cloud region (e.g. us-south, eu-gb, au-syd)"
  type        = string
  default     = "us-south"
}

variable "resource_group_name" {
  description = "Name of the IBM Cloud Resource Group"
  type        = string
  default     = "Default"
}

# ── Tagging ──────────────────────────────────────────────────────────────────
variable "tag_name" {
  description = "Tag key applied to every resource"
  type        = string
  default     = "Environment"
}

variable "tag_value" {
  description = "Tag value applied to every resource"
  type        = string
  default     = "Production"
}

# ── VPC / Networking ─────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "Address prefix for the VPC (used as the first address prefix)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "number_of_zones" {
  description = "Number of availability zones to deploy into (2, 3, or 4)"
  type        = number
  default     = 2
}

variable "create_private_subnets" {
  description = "Create private subnets with NAT (public-gateway) egress"
  type        = bool
  default     = true
}

variable "create_additional_private_subnets" {
  description = "Create additional private subnets (B-series) with dedicated ACLs"
  type        = bool
  default     = false
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per zone)"
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20", "10.0.176.0/20"]
}

variable "private_subnet_a_cidrs" {
  description = "CIDR blocks for private A subnets (one per zone)"
  type        = list(string)
  default     = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19", "10.0.96.0/19"]
}

variable "private_subnet_b_cidrs" {
  description = "CIDR blocks for private B subnets with dedicated ACLs (one per zone)"
  type        = list(string)
  default     = ["10.0.192.0/21", "10.0.200.0/21", "10.0.208.0/21", "10.0.216.0/21"]
}

# ── Compute / Webserver ───────────────────────────────────────────────────────
variable "windows_image_id" {
  description = "IBM Cloud VPC stock image ID for Windows Server"
  type        = string
  # Find current IDs with: ibmcloud is images --visibility public | grep -i windows
  default     = ""
}

variable "instance_profile" {
  description = "VPC instance profile (e.g. bx2-4x16)"
  type        = string
  default     = "bx2-4x16"
}

variable "ssh_key_name" {
  description = "Name of an existing VPC SSH key (used for instance access)"
  type        = string
  default     = ""
}

variable "webserver_min_instances" {
  description = "Minimum number of webserver instances"
  type        = number
  default     = 1
}

variable "webserver_max_instances" {
  description = "Maximum number of webserver instances"
  type        = number
  default     = 4
}

variable "webserver_user_data" {
  description = "User-data / cloud-init script for Windows webserver instances"
  type        = string
  default     = ""
}

# ── Database ──────────────────────────────────────────────────────────────────
variable "db_admin_password" {
  description = "Admin password for the managed database instance"
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_plan" {
  description = "IBM Cloud Databases for PostgreSQL plan (standard or enterprise)"
  type        = string
  default     = "standard"
}

# ── IOPS calculation ──────────────────────────────────────────────────────────
variable "iops_ratio" {
  description = "IOPS ratio (multiplier)"
  type        = number
  default     = 3
}

variable "allocated_storage_gb" {
  description = "Allocated storage in GB"
  type        = number
  default     = 500
}
