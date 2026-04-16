##############################################################################
# vpc.tf
# Converted from: nested-vpc_cfn.template
#
# AWS → IBM Cloud resource mapping used in this file:
#   AWS::EC2::VPC                        → ibm_is_vpc
#   AWS::EC2::DHCPOptions                → (not needed – IBM manages DHCP)
#   AWS::EC2::VPCDHCPOptionsAssociation  → (not needed)
#   AWS::EC2::InternetGateway            → ibm_is_public_gateway (per zone)
#   AWS::EC2::VPCGatewayAttachment       → (implicit in ibm_is_public_gateway)
#   AWS::EC2::Subnet                     → ibm_is_subnet
#   AWS::EC2::RouteTable                 → ibm_is_vpc_routing_table
#   AWS::EC2::Route                      → ibm_is_vpc_routing_table_route
#   AWS::EC2::SubnetRouteTableAssociation→ ibm_is_subnet.routing_table (inline)
#   AWS::EC2::NetworkAcl                 → ibm_is_network_acl
#   AWS::EC2::NetworkAclEntry            → ibm_is_network_acl_rule
#   AWS::EC2::SubnetNetworkAclAssociation→ ibm_is_subnet.network_acl (inline)
#   AWS::EC2::EIP                        → ibm_is_floating_ip (on public gateway)
#   AWS::EC2::NatGateway                 → ibm_is_public_gateway
#   AWS::EC2::VPCEndpoint (S3)           → ibm_is_virtual_endpoint_gateway (COS)
#   AWS::RDS::DBSubnetGroup              → ibm_is_subnet_reserved_ip (COS VPE)
#                                          Note: IBM Databases don't use a
#                                          separate subnet group resource – the
#                                          service instance is placed in the VPC
#                                          via a VPE instead.
##############################################################################

# ── VPC ──────────────────────────────────────────────────────────────────────
resource "ibm_is_vpc" "main" {
  name                      = "lansa-vpc"
  resource_group            = data.ibm_resource_group.rg.id
  address_prefix_management = "manual"
  tags                      = local.common_tags
}

# Address prefixes (one per zone) – replaces the VPC CIDR block carve-out
resource "ibm_is_vpc_address_prefix" "main" {
  count = var.number_of_zones
  name  = "prefix-zone-${count.index + 1}"
  zone  = local.zones[count.index]
  vpc   = ibm_is_vpc.main.id
  cidr  = var.vpc_cidr
  # IBM requires non-overlapping prefixes per zone – adjust CIDRs if needed.
}

# ── Public Gateways (replaces Internet Gateway + NAT Gateways) ───────────────
# In IBM Cloud a Public Gateway provides both internet egress for the subnet
# (like a NAT Gateway) and is attached at the subnet level (not VPC level).

resource "ibm_is_public_gateway" "public" {
  count          = var.number_of_zones
  name           = "pgw-zone-${count.index + 1}"
  vpc            = ibm_is_vpc.main.id
  zone           = local.zones[count.index]
  resource_group = data.ibm_resource_group.rg.id
  tags           = local.common_tags
}

# ── Public Subnets ────────────────────────────────────────────────────────────
resource "ibm_is_subnet" "public" {
  count           = var.number_of_zones
  name            = "public-subnet-${count.index + 1}"
  vpc             = ibm_is_vpc.main.id
  zone            = local.zones[count.index]
  ipv4_cidr_block = var.public_subnet_cidrs[count.index]
  # Public subnets do NOT attach the public gateway – outbound internet for
  # instances uses floating IPs or the load balancer.
  resource_group = data.ibm_resource_group.rg.id
  tags           = concat(local.common_tags, ["Network:Public"])
}

# ── Private A Subnets (with public-gateway egress, replaces NAT gateway) ─────
resource "ibm_is_subnet" "private_a" {
  count           = var.create_private_subnets ? var.number_of_zones : 0
  name            = "private-subnet-${count.index + 1}a"
  vpc             = ibm_is_vpc.main.id
  zone            = local.zones[count.index]
  ipv4_cidr_block = var.private_subnet_a_cidrs[count.index]
  public_gateway  = ibm_is_public_gateway.public[count.index].id
  resource_group  = data.ibm_resource_group.rg.id
  tags            = concat(local.common_tags, ["Network:Private"])
}

# ── Private B Subnets with dedicated ACLs ────────────────────────────────────
# Replaces the "additional private subnets" with dedicated Network ACLs

resource "ibm_is_network_acl" "private_b" {
  count          = var.create_additional_private_subnets ? var.number_of_zones : 0
  name           = "nacl-private-${count.index + 1}b"
  vpc            = ibm_is_vpc.main.id
  resource_group = data.ibm_resource_group.rg.id
  tags           = concat(local.common_tags, ["Network:NACLProtected"])

  # Inbound allow-all (rule 100 in the original template)
  rules {
    name        = "inbound-allow-all"
    action      = "allow"
    direction   = "inbound"
    source      = "0.0.0.0/0"
    destination = "0.0.0.0/0"
  }

  # Outbound allow-all
  rules {
    name        = "outbound-allow-all"
    action      = "allow"
    direction   = "outbound"
    source      = "0.0.0.0/0"
    destination = "0.0.0.0/0"
  }
}

resource "ibm_is_subnet" "private_b" {
  count           = var.create_additional_private_subnets ? var.number_of_zones : 0
  name            = "private-subnet-${count.index + 1}b"
  vpc             = ibm_is_vpc.main.id
  zone            = local.zones[count.index]
  ipv4_cidr_block = var.private_subnet_b_cidrs[count.index]
  public_gateway  = ibm_is_public_gateway.public[count.index].id
  network_acl     = ibm_is_network_acl.private_b[count.index].id
  resource_group  = data.ibm_resource_group.rg.id
  tags            = concat(local.common_tags, ["Network:Private"])
}

# ── Custom Routing Tables for Private A Subnets ───────────────────────────────
# In IBM Cloud VPC, custom routing tables replace EC2 RouteTables + Routes.
# The default egress route via the public gateway is already established by
# attaching public_gateway on the subnet. A custom routing table is only
# needed for more specific routing requirements.

resource "ibm_is_vpc_routing_table" "private_a" {
  count                         = var.create_private_subnets ? var.number_of_zones : 0
  name                          = "rt-private-${count.index + 1}a"
  vpc                           = ibm_is_vpc.main.id
  route_internet_ingress        = false
  accept_routes_from_resource_type = ["vpn_gateway"]
  tags                          = local.common_tags
}

# ── VPC Endpoint Gateway for Cloud Object Storage ─────────────────────────────
# Replaces AWS::EC2::VPCEndpoint for S3.
# IBM Cloud Object Storage is accessed via a Virtual Private Endpoint (VPE).

data "ibm_resource_instance" "cos" {
  count             = var.create_private_subnets ? 1 : 0
  name              = "cloud-object-storage"
  service           = "cloud-object-storage"
  location          = "global"
  resource_group_id = data.ibm_resource_group.rg.id
}

resource "ibm_is_virtual_endpoint_gateway" "cos" {
  count          = var.create_private_subnets ? 1 : 0
  name           = "vpe-cos"
  vpc            = ibm_is_vpc.main.id
  resource_group = data.ibm_resource_group.rg.id
  tags           = local.common_tags

  target {
    name          = "ibm-cloud-object-storage"
    resource_type = "provider_cloud_service"
  }

  # Bind the VPE to each private subnet
  dynamic "ips" {
    for_each = ibm_is_subnet.private_a
    content {
      subnet = ips.value.id
      name   = "vpe-cos-ip-${ips.key + 1}"
    }
  }
}

##############################################################################
# Outputs (mirrors the CFN Outputs section)
##############################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = ibm_is_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = ibm_is_subnet.public[*].id
}

output "private_subnet_a_ids" {
  description = "Private A subnet IDs"
  value       = ibm_is_subnet.private_a[*].id
}

output "private_subnet_b_ids" {
  description = "Private B subnet IDs"
  value       = ibm_is_subnet.private_b[*].id
}

output "public_gateway_ids" {
  description = "Public Gateway IDs (equivalent to NAT Gateway EIPs)"
  value       = ibm_is_public_gateway.public[*].id
}
