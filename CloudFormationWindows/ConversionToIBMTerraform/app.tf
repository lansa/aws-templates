##############################################################################
# app.tf
# Converted from: lansa-master-win_cfn.template
#
# AWS → IBM Cloud resource mapping used in this file:
#   AWS::IAM::Role             → ibm_iam_service_id + ibm_iam_service_policy
#   AWS::IAM::InstanceProfile  → ibm_iam_trusted_profile (instances use
#                                 Trusted Profiles instead of instance profiles)
#   AWS::EC2::SecurityGroup    → ibm_is_security_group
#   AWS::EC2::SecurityGroupIngress → ibm_is_security_group_rule
#   AWS::ElasticLoadBalancing::LoadBalancer → ibm_is_lb + ibm_is_lb_listener
#                                              + ibm_is_lb_pool
#   AWS::RDS::DBInstance       → ibm_resource_instance (Databases for PostgreSQL)
#   AWS::Logs::LogGroup        → ibm_resource_instance (IBM Log Analysis)
#   AWS::CloudFormation::Stack → Terraform module reference (vpc outputs used
#                                 directly via resource references)
##############################################################################

# ── IAM Service ID (replaces IAM Role + InstanceProfile) ─────────────────────
# In IBM Cloud, VSIs authenticate using Trusted Profiles (metadata service)
# rather than instance profiles. The Service ID below is used for programmatic
# access by the application (e.g. to write to COS or call Watson APIs).

resource "ibm_iam_service_id" "app" {
  name        = "lansa-app-service-id"
  description = "Service identity for LANSA application instances"
  tags        = local.common_tags
}

# Grant the service ID access to Cloud Object Storage
resource "ibm_iam_service_policy" "app_cos" {
  iam_service_id = ibm_iam_service_id.app.id

  roles = ["Writer"]

  resources {
    service = "cloud-object-storage"
  }
}

# Trusted Profile – allows VSIs to assume this identity via the metadata service
# (equivalent to an EC2 Instance Profile bound to an IAM Role)
resource "ibm_iam_trusted_profile" "app" {
  name        = "lansa-instance-profile"
  description = "Trusted profile for LANSA Windows instances"
}

resource "ibm_iam_trusted_profile_claim_rule" "app_vsi" {
  profile_id = ibm_iam_trusted_profile.app.id
  type       = "Profile-SAML"
  name       = "vsi-claim-rule"
  realm_name = "IBMid"
  conditions {
    claim    = "blueGroups"
    operator = "CONTAINS"
    value    = "\"lansa-app\""
  }
}

# ── Security Groups ───────────────────────────────────────────────────────────

# Web-tier security group (replaces AWS::EC2::SecurityGroup for the web layer)
resource "ibm_is_security_group" "web" {
  name           = "lansa-web-sg"
  vpc            = ibm_is_vpc.main.id
  resource_group = data.ibm_resource_group.rg.id
  tags           = local.common_tags
}

# Allow HTTP inbound from anywhere (replaces SecurityGroupIngress port 80)
resource "ibm_is_security_group_rule" "web_http_in" {
  group     = ibm_is_security_group.web.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  tcp {
    port_min = 80
    port_max = 80
  }
}

# Allow HTTPS inbound
resource "ibm_is_security_group_rule" "web_https_in" {
  group     = ibm_is_security_group.web.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  tcp {
    port_min = 443
    port_max = 443
  }
}

# Allow RDP for management (Windows)
resource "ibm_is_security_group_rule" "web_rdp_in" {
  group     = ibm_is_security_group.web.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  tcp {
    port_min = 3389
    port_max = 3389
  }
}

# Allow all outbound
resource "ibm_is_security_group_rule" "web_all_out" {
  group     = ibm_is_security_group.web.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

# Database-tier security group
resource "ibm_is_security_group" "db" {
  name           = "lansa-db-sg"
  vpc            = ibm_is_vpc.main.id
  resource_group = data.ibm_resource_group.rg.id
  tags           = local.common_tags
}

# Allow Postgres (5432) inbound from web SG
resource "ibm_is_security_group_rule" "db_postgres_in" {
  group     = ibm_is_security_group.db.id
  direction = "inbound"
  remote    = ibm_is_security_group.web.id
  tcp {
    port_min = 5432
    port_max = 5432
  }
}

# ── Load Balancer (replaces AWS::ElasticLoadBalancing::LoadBalancer) ──────────
# Classic ELB → IBM Application Load Balancer (ibm_is_lb, type = "public")

resource "ibm_is_lb" "web" {
  name           = "lansa-web-lb"
  type           = "public"
  subnets        = ibm_is_subnet.public[*].id
  security_groups = [ibm_is_security_group.web.id]
  resource_group = data.ibm_resource_group.rg.id
  tags           = local.common_tags
}

resource "ibm_is_lb_pool" "web" {
  name                = "lansa-web-pool"
  lb                  = ibm_is_lb.web.id
  algorithm           = "round_robin"
  protocol            = "http"
  health_delay        = 10
  health_retries      = 2
  health_timeout      = 5
  health_type         = "http"
  health_monitor_url  = "/health"
  health_monitor_port = 80
}

resource "ibm_is_lb_listener" "web_http" {
  lb           = ibm_is_lb.web.id
  port         = 80
  protocol     = "http"
  default_pool = ibm_is_lb_pool.web.id
}

resource "ibm_is_lb_listener" "web_https" {
  lb       = ibm_is_lb.web.id
  port     = 443
  protocol = "https"
  # certificate_instance = "<CRN of certificate in Secrets Manager>"
  default_pool = ibm_is_lb_pool.web.id
}

# ── Managed Database (replaces AWS::RDS::DBInstance) ─────────────────────────
# IBM Cloud Databases for PostgreSQL is the closest equivalent to RDS Postgres.
# For MS SQL Server workloads, consider IBM Db2 on Cloud or a self-managed
# Windows SQL Server VSI.

resource "ibm_resource_instance" "db" {
  name              = "lansa-postgres-db"
  service           = "databases-for-postgresql"
  plan              = var.db_plan           # "standard" or "enterprise"
  location          = var.region
  resource_group_id = data.ibm_resource_group.rg.id
  tags              = local.common_tags

  parameters = {
    # Calculated IOPS value comes from the calculate_iops local (see functions.tf)
    disk_iops        = local.calculated_iops
    members_memory_allocation_mb = 4096
    members_disk_allocation_mb   = var.allocated_storage_gb * 1024
    version                      = "15"
  }
}

# ── IBM Log Analysis (replaces AWS::Logs::LogGroup) ───────────────────────────
# IBM Log Analysis (formerly LogDNA) is the IBM Cloud equivalent of CloudWatch Logs.

resource "ibm_resource_instance" "log_analysis" {
  name              = "lansa-log-analysis"
  service           = "logdna"
  plan              = "7-day"    # 7-day retention; adjust to "14-day", "30-day", etc.
  location          = var.region
  resource_group_id = data.ibm_resource_group.rg.id
  tags              = local.common_tags
}

resource "ibm_resource_key" "log_analysis_key" {
  name                 = "lansa-log-key"
  resource_instance_id = ibm_resource_instance.log_analysis.id
  role                 = "Manager"
}

##############################################################################
# Outputs
##############################################################################

output "load_balancer_hostname" {
  description = "DNS hostname of the Application Load Balancer"
  value       = ibm_is_lb.web.hostname
}

output "database_crn" {
  description = "CRN of the managed PostgreSQL database"
  value       = ibm_resource_instance.db.crn
}

output "log_analysis_ingestion_key" {
  description = "Log Analysis ingestion key (sensitive)"
  value       = ibm_resource_key.log_analysis_key.credentials["ingestion_key"]
  sensitive   = true
}
