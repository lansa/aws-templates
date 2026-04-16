##############################################################################
# compute.tf
# Converted from: webserver-win_cfn.template
#
# AWS → IBM Cloud resource mapping used in this file:
#   AWS::EC2::LaunchTemplate            → ibm_is_instance_template
#   AWS::AutoScaling::AutoScalingGroup  → ibm_is_instance_group
#   AWS::AutoScaling::ScalingPolicy     → ibm_is_instance_group_manager
#                                          + ibm_is_instance_group_manager_policy
#   AWS::CloudWatch::Alarm              → IBM Cloud Monitoring (Sysdig) alert
#                                          Note: No native Terraform resource for
#                                          Sysdig alerts in the IBM provider yet.
#                                          Use the ibm_resource_instance to
#                                          provision Monitoring, then configure
#                                          alerts via the Sysdig API/UI.
#   AWS::CloudFormation::WaitCondition  → null_resource (see note below)
#   AWS::CloudFormation::WaitConditionHandle → null_resource
##############################################################################

# ── Data source: look up the Windows stock image ─────────────────────────────
data "ibm_is_image" "windows" {
  # If var.windows_image_id is provided use it directly, otherwise look up
  # the latest Windows Server 2022 stock image by name filter.
  name = var.windows_image_id != "" ? null : "ibm-windows-server-2022-full-standard-amd64-12"
  # Set var.windows_image_id to override with a specific image CRN/ID.
}

locals {
  windows_image_id = var.windows_image_id != "" ? var.windows_image_id : data.ibm_is_image.windows.id
}

# ── SSH Key (optional – Windows typically uses RDP, but a key is required) ───
data "ibm_is_ssh_key" "default" {
  count = var.ssh_key_name != "" ? 1 : 0
  name  = var.ssh_key_name
}

# ── Instance Template (replaces AWS::EC2::LaunchTemplate) ────────────────────
resource "ibm_is_instance_template" "webserver" {
  name    = "lansa-webserver-template"
  image   = local.windows_image_id
  profile = var.instance_profile
  vpc     = ibm_is_vpc.main.id

  # Place in the first private subnet; the instance group will spread across zones
  zone = local.zones[0]

  primary_network_interface {
    subnet          = ibm_is_subnet.private_a[0].id
    security_groups = [ibm_is_security_group.web.id]
  }

  keys = var.ssh_key_name != "" ? [data.ibm_is_ssh_key.default[0].id] : []

  user_data = var.webserver_user_data

  # Boot volume
  boot_volume {
    name       = "webserver-boot"
    # IBM Cloud custom IOPS is set at the volume level via volume profile
    # "custom" allows specifying IOPS; use local.calculated_iops from functions.tf
    profile    = "general-purpose"
    # To use calculated IOPS uncomment and set profile to "custom":
    # iops      = local.calculated_iops
    encryption = ""  # Set to a KMS key CRN for encryption at rest
  }

  metadata_service {
    enabled = true   # Required for Trusted Profile authentication
  }

  tags = local.common_tags
}

# ── Instance Group (replaces AWS::AutoScaling::AutoScalingGroup) ──────────────
resource "ibm_is_instance_group" "webserver" {
  name               = "lansa-webserver-asg"
  instance_template  = ibm_is_instance_template.webserver.id
  instance_count     = var.webserver_min_instances
  resource_group     = data.ibm_resource_group.rg.id

  # Spread across all private A subnets (one per zone)
  subnets = ibm_is_subnet.private_a[*].id

  # Attach to the load balancer pool
  load_balancer      = ibm_is_lb.web.id
  load_balancer_pool = ibm_is_lb_pool.web.id
  application_port   = 80

  tags = local.common_tags

  timeouts {
    create = "15m"
    update = "15m"
    delete = "10m"
  }
}

# ── Instance Group Manager (auto-scaling, replaces ScalingPolicy) ─────────────
resource "ibm_is_instance_group_manager" "webserver" {
  name                 = "lansa-webserver-manager"
  instance_group       = ibm_is_instance_group.webserver.id
  manager_type         = "autoscale"
  enable_manager       = true
  min_membership_count = var.webserver_min_instances
  max_membership_count = var.webserver_max_instances
  # Cooldown period in seconds (replaces Cooldown in CFN ScalingPolicy)
  aggregation_window   = 90
  cooldown             = 300
}

# Scale-out policy: add 1 instance when CPU > 70%
# (replaces AWS::AutoScaling::ScalingPolicy + AWS::CloudWatch::Alarm ScaleUp)
resource "ibm_is_instance_group_manager_policy" "scale_out" {
  name                   = "lansa-scale-out"
  instance_group         = ibm_is_instance_group.webserver.id
  instance_group_manager = ibm_is_instance_group_manager.webserver.manager_id
  policy_type            = "target"
  metric_type            = "cpu"
  metric_value           = 70
}

# Scale-in policy: remove 1 instance when CPU < 30%
# (replaces AWS::AutoScaling::ScalingPolicy + AWS::CloudWatch::Alarm ScaleDown)
resource "ibm_is_instance_group_manager_policy" "scale_in" {
  name                   = "lansa-scale-in"
  instance_group         = ibm_is_instance_group.webserver.id
  instance_group_manager = ibm_is_instance_group_manager.webserver.manager_id
  policy_type            = "target"
  metric_type            = "cpu"
  metric_value           = 30
}

# ── IBM Cloud Monitoring (replaces CloudWatch Alarm + metrics) ────────────────
# Provision a Monitoring instance (Sysdig-based).
# NOTE: Detailed alert rules are configured via the Sysdig API or UI after
# provisioning. The IBM Terraform provider does not yet expose alert resources.

resource "ibm_resource_instance" "monitoring" {
  name              = "lansa-monitoring"
  service           = "sysdig-monitor"
  plan              = "graduated-tier"
  location          = var.region
  resource_group_id = data.ibm_resource_group.rg.id
  tags              = local.common_tags
}

resource "ibm_resource_key" "monitoring_key" {
  name                 = "lansa-monitoring-key"
  resource_instance_id = ibm_resource_instance.monitoring.id
  role                 = "Manager"
}

# ── Wait / Readiness Signal ────────────────────────────────────────────────────
# AWS::CloudFormation::WaitCondition / WaitConditionHandle have no direct
# equivalent in Terraform. The null_resource below with a local-exec trigger
# can simulate a readiness check – poll the load balancer until it responds.
# For Windows instances a WinRM / SSM Session Manager approach is preferred.

resource "null_resource" "webserver_ready" {
  depends_on = [ibm_is_instance_group.webserver, ibm_is_lb.web]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for load balancer to become active..."
      for i in $(seq 1 30); do
        STATUS=$(ibmcloud is lb ${ibm_is_lb.web.id} --output json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('operating_status','unknown'))" 2>/dev/null)
        echo "LB status: $STATUS"
        if [ "$STATUS" = "online" ]; then exit 0; fi
        sleep 30
      done
      echo "Timed out waiting for load balancer"
      exit 1
    EOT
  }
}

##############################################################################
# Outputs
##############################################################################

output "instance_group_id" {
  description = "ID of the auto-scaling instance group"
  value       = ibm_is_instance_group.webserver.id
}

output "instance_template_id" {
  description = "ID of the instance template"
  value       = ibm_is_instance_template.webserver.id
}

output "monitoring_access_key" {
  description = "IBM Cloud Monitoring access key"
  value       = ibm_resource_key.monitoring_key.credentials["Sysdig Access Key"]
  sensitive   = true
}
