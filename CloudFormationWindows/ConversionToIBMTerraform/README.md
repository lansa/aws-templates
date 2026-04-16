# AWS CFN → IBM Cloud Terraform Migration

## Resource Mapping Table

| AWS CFN Resource | IBM Cloud Equivalent | Terraform Resource |
|---|---|---|
| `AWS::EC2::VPC` | IBM Cloud VPC | `ibm_is_vpc` |
| `AWS::EC2::DHCPOptions` / `VPCDHCPOptionsAssociation` | Managed automatically | *(not needed)* |
| `AWS::EC2::InternetGateway` + `VPCGatewayAttachment` | Public Gateway (per zone) | `ibm_is_public_gateway` |
| `AWS::EC2::NatGateway` | Public Gateway (attached to subnet) | `ibm_is_public_gateway` |
| `AWS::EC2::EIP` | Floating IP | `ibm_is_floating_ip` |
| `AWS::EC2::Subnet` | VPC Subnet | `ibm_is_subnet` |
| `AWS::EC2::RouteTable` | VPC Routing Table | `ibm_is_vpc_routing_table` |
| `AWS::EC2::Route` | Routing Table Route | `ibm_is_vpc_routing_table_route` |
| `AWS::EC2::SubnetRouteTableAssociation` | Inline on `ibm_is_subnet` | `ibm_is_subnet.routing_table` |
| `AWS::EC2::NetworkAcl` | Network ACL | `ibm_is_network_acl` |
| `AWS::EC2::NetworkAclEntry` | Network ACL Rule | `ibm_is_network_acl_rule` |
| `AWS::EC2::SubnetNetworkAclAssociation` | Inline on `ibm_is_subnet` | `ibm_is_subnet.network_acl` |
| `AWS::EC2::VPCEndpoint` (S3) | Virtual Private Endpoint Gateway (COS) | `ibm_is_virtual_endpoint_gateway` |
| `AWS::EC2::SecurityGroup` | Security Group | `ibm_is_security_group` |
| `AWS::EC2::SecurityGroupIngress` | Security Group Rule | `ibm_is_security_group_rule` |
| `AWS::EC2::LaunchTemplate` | Instance Template | `ibm_is_instance_template` |
| `AWS::AutoScaling::AutoScalingGroup` | Instance Group | `ibm_is_instance_group` |
| `AWS::AutoScaling::ScalingPolicy` | Instance Group Manager + Policy | `ibm_is_instance_group_manager` + `ibm_is_instance_group_manager_policy` |
| `AWS::CloudWatch::Alarm` | IBM Cloud Monitoring (Sysdig) | `ibm_resource_instance` (sysdig-monitor) |
| `AWS::ElasticLoadBalancing::LoadBalancer` | IBM Application Load Balancer | `ibm_is_lb` + `ibm_is_lb_pool` + `ibm_is_lb_listener` |
| `AWS::RDS::DBInstance` (PostgreSQL) | IBM Databases for PostgreSQL | `ibm_resource_instance` (databases-for-postgresql) |
| `AWS::RDS::DBSubnetGroup` | Not needed (VPE used instead) | `ibm_is_virtual_endpoint_gateway` |
| `AWS::IAM::Role` | IAM Service ID | `ibm_iam_service_id` |
| `AWS::IAM::InstanceProfile` | IAM Trusted Profile | `ibm_iam_trusted_profile` |
| `AWS::Lambda::Function` | IBM Cloud Functions Action | `ibm_function_action` |
| `AWS::Logs::LogGroup` | IBM Log Analysis (LogDNA) | `ibm_resource_instance` (logdna) |
| `AWS::CloudFormation::Stack` | Terraform module | `module {}` |
| `AWS::CloudFormation::WaitCondition` | `null_resource` + `local-exec` | `null_resource` |

---

## File Structure

```
ibm-terraform/
├── providers.tf    # IBM Cloud provider, data sources, common locals
├── variables.tf    # All input variables
├── vpc.tf          # VPC, subnets, gateways, ACLs (from nested-vpc_cfn.template)
├── app.tf          # IAM, security groups, load balancer, DB, logging (from lansa-master-win_cfn.template)
├── compute.tf      # Instance template, auto-scaling group, monitoring (from webserver-win_cfn.template)
└── functions.tf    # IOPS calculation logic (from calculate-iops_cfn.template)
```

---

## Key Architectural Differences

### Networking
- IBM Cloud VPC uses **address prefixes** per zone rather than a single VPC CIDR.
- The **Public Gateway** in IBM Cloud combines the Internet Gateway and NAT Gateway concepts: it gives outbound internet access to all instances in a subnet without assigning floating IPs.
- **DHCP** is managed automatically by IBM Cloud — no `DHCPOptions` resource is needed.
- AWS **Availability Zones** map to IBM Cloud **zones** within a region (e.g. `us-south-1`, `us-south-2`, `us-south-3`).

### Compute
- AWS **EC2 Instance Profiles** → IBM **IAM Trusted Profiles** (metadata service endpoint).
- AWS **Auto Scaling Groups** → IBM **Instance Groups** with an attached Instance Group Manager.
- CloudWatch CPU alarms for scaling are replaced by IBM Instance Group Manager **target policies** which handle the threshold logic natively.

### Database
- AWS RDS does not use a subnet group in IBM Cloud — instead, a **Virtual Private Endpoint (VPE)** connects the managed database service to the VPC.
- For MS SQL Server workloads (common in Windows stacks), consider a self-managed SQL Server on a Windows VSI, or IBM Db2 on Cloud.

### Serverless / Lambda
- The `calculate-iops` Lambda is a simple arithmetic operation — this is replaced by a **Terraform `local` value**, eliminating any serverless infrastructure.
- If a true IBM Cloud Functions equivalent is needed, use `ibm_function_action` (commented out in `functions.tf`).

### Logging & Monitoring
- AWS CloudWatch Logs → **IBM Log Analysis** (logdna)
- AWS CloudWatch Metrics/Alarms → **IBM Cloud Monitoring** (sysdig-monitor)

---

## Getting Started

```bash
# 1. Set your IBM Cloud API key
export TF_VAR_ibmcloud_api_key="<your-api-key>"

# 2. Initialise Terraform
terraform init

# 3. Preview changes
terraform plan -var="region=au-syd"

# 4. Apply
terraform apply -var="region=au-syd"
```

### Finding a Windows Image ID
```bash
ibmcloud is images --visibility public --output json | \
  python3 -c "import json,sys; [print(i['id'], i['name']) for i in json.load(sys.stdin) if 'windows' in i['name'].lower()]"
```

---

## Notes & Caveats

1. **Availability Zones**: IBM Cloud regions have 3 zones. The `number_of_zones` variable caps at 3 for most regions (the CFN template supported up to 4).
2. **IOPS**: IBM Cloud volume IOPS profiles differ from AWS. The `custom` volume profile allows explicit IOPS values; `general-purpose` and `5iops-tier` are the common alternatives.
3. **Windows Licensing**: IBM Cloud includes the Windows Server license in the stock image cost — no separate BYOL step is needed.
4. **Nested Stacks**: The CFN `AWS::CloudFormation::Stack` reference is replaced by directly referencing Terraform resource outputs across files (all files share the same state).
5. **Wait Conditions**: The `null_resource` approach requires the `ibmcloud` CLI to be installed locally. Alternatively, use `terraform_data` with a polling script.
