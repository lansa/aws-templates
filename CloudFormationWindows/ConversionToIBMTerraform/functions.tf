##############################################################################
# functions.tf
# Converted from: calculate-iops_cfn.template
#
# AWS → IBM Cloud resource mapping used in this file:
#   AWS::IAM::Role          → ibm_iam_service_id + ibm_iam_service_policy
#   AWS::Lambda::Function   → ibm_function_action  (IBM Cloud Functions)
#                             OR: Terraform local value (see preferred approach)
#   Custom::CalculateIops   → Terraform local value  ← PREFERRED APPROACH
#
# ─────────────────────────────────────────────────────────────────────────────
# Design note:
# The CFN template uses a Lambda-backed Custom Resource purely to perform a
# simple arithmetic computation (iops = ratio × storage, clamped to 1000–64000)
# at deploy time. In Terraform this is trivially expressed as a local value –
# no function or serverless infrastructure is required at all. The local value
# approach is used below.
#
# If you DO need IBM Cloud Functions for other Lambda workloads, the
# ibm_function_action resource is shown in the commented section at the bottom.
##############################################################################

# ── IOPS Calculation (replaces Lambda Custom Resource) ───────────────────────
locals {
  # Direct equivalent of the Lambda handler logic:
  #   result = ratio * storage
  #   if result < 1000: result = 1000
  #   if result > 64000: result = 64000
  calculated_iops = max(1000, min(64000, var.iops_ratio * var.allocated_storage_gb))
}

output "calculated_iops" {
  description = "Calculated IOPS value (equivalent to CFN CalculateIops Output)"
  value       = local.calculated_iops
}

##############################################################################
# OPTIONAL: IBM Cloud Functions equivalent of the Lambda function
# Uncomment this section if you want a serverless function for IOPS calculation
# rather than a Terraform local value (e.g. if it needs to be called at runtime).
##############################################################################

# resource "ibm_iam_service_id" "functions" {
#   name        = "lansa-functions-service-id"
#   description = "Service identity for IBM Cloud Functions actions"
#   tags        = local.common_tags
# }
#
# resource "ibm_iam_service_policy" "functions_logs" {
#   iam_service_id = ibm_iam_service_id.functions.id
#   roles          = ["Writer"]
#   resources {
#     service = "logdna"
#   }
# }
#
# # IBM Cloud Functions namespace (replaces Lambda's account-level scoping)
# resource "ibm_function_namespace" "lansa" {
#   name              = "lansa-namespace"
#   resource_group_id = data.ibm_resource_group.rg.id
# }
#
# # IBM Cloud Functions action (equivalent to AWS::Lambda::Function)
# # Runtime mapping: python3.13 → python:3.11 (latest available in ICF)
# resource "ibm_function_action" "calculate_iops" {
#   name      = "calculate-iops"
#   namespace = ibm_function_namespace.lansa.name
#
#   exec {
#     kind = "python:3.11"
#     code = <<-PYTHON
#       def main(params):
#           ratio   = int(params.get("iops_ratio",   3))
#           storage = int(params.get("allocated_gb", 500))
#           result  = ratio * storage
#           if result < 1000:
#               result = 1000
#           elif result > 64000:
#               result = 64000
#           return {"iops": result}
#     PYTHON
#   }
#
#   limits {
#     timeout    = 5000   # milliseconds
#     memory     = 256    # MB
#     log_size   = 10     # MB
#   }
# }
