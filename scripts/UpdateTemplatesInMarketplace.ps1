# UpdateMarketplaceTemplates.ps1
# This script updates CloudFormation template URLs for all delivery options in multiple AWS Marketplace AMI-based products.
# It uses AWS PowerShell cmdlets to describe products, identify versions and delivery options, and submit change sets to update templates.
# Assumptions:
# - AWS PowerShell module is installed (e.g., AWS.Tools.MarketplaceCatalog).
# - Credentials are set via environment variables or default profile.
# - Updates the first version of each product; assumes version format aligns with $Version (e.g., "15.0.19").
# - Hardcoded list of Product IDs and five specific templates per product.
# - Templates are sourced from a fixed S3 URL: https://lansa.s3.ap-southeast-2.amazonaws.com/templates/support/scalable/.
# - Runs in Azure DevOps self-hosted Windows agent context.
# - Compatible with PowerShell 5.1 (removes ?? operator for compatibility).

param (
    [Parameter(Mandatory=$false)]
    [string]$Version = "15.0.19"
)

# Import required modules
# Import-Module AWS.Tools.Common
# Import-Module AWS.Tools.MarketplaceCatalog

# Set default region for Marketplace Catalog API (global service, but set for consistency)
Set-DefaultAWSRegion -Region 'us-east-1'

# Hardcoded list of Product IDs
$productIds = @(
    'prod-7c4xdvxkskdfs',  # English w19d
    'prod-csfkcd5qvncle'   # Japanese w19d
    # Add other product IDs as needed, e.g., 'prod-xxx' for w25d_eng, w25d_jpn, etc.
)

# Template names (same for all products)
$templateNames = @(
    'lansa-stack-type-win.cfn.template',
    'lansa-master-win.cfn.template',
    'lansa-template1.cfn.template',  # Replace with actual template names
    'lansa-template2.cfn.template',  # Replace with actual template names
    'lansa-template3.cfn.template'   # Replace with actual template names
)

# Base S3 URL for templates
$baseS3Url = "https://lansa.s3.ap-southeast-2.amazonaws.com/templates/support/scalable/"

try {
    foreach ($productId in $productIds) {
        Write-Host "Processing product: $productId"

        # Step 1: Describe the product entity to get details
        $entityResponse = Get-MCATEntity -Catalog 'AWSMarketplace' -EntityId $productId # -Type 'AmiProduct@1.0'
        if (-not $entityResponse) {
            Write-Error "Failed to retrieve entity for product $productId"
            continue
        }
        $entityResponse | Out-Default | Write-Host

        $productDetails = $entityResponse.Details | ConvertFrom-Json
        if (-not $productDetails) {
            Write-Error "Failed to retrieve details for product $productId"
            continue
        }
        $productDetails | Format-List | Out-Default | Write-Host

        # Step 2: Find the target version (assume first version; customize if needed)
        if ($productDetails.Versions.Count -eq 0) {
            Write-Error "No versions found for product $productId"
            continue
        }
        $productDetails.Versions | ForEach-Object { Write-Host "Available Version: $($_.VersionTitle)" }
        $targetVersion = $productDetails.Versions | Where-Object { $_.VersionTitle -eq $Version }
        if (-not $targetVersion) {
            Write-Error "Version $Version not found for product $productId"
            continue
        }
        $versionIdentifier = "$($targetVersion.Id)@1"  # Assume revision 1

        # Step 3: Get all delivery options for the version
        $deliveryOptions = $targetVersion.DeliveryOptions | Where-Object { $_.Details.DeploymentTemplateDeliveryOptionDetails }
        if (-not $deliveryOptions) {
            Write-Error "No CloudFormation delivery options found in version $Version for product $productId"
            continue
        }

        # Step 4: Construct the DetailsDocument with updated template URLs
        $deliveryOptionsUpdates = @()
        foreach ($deliveryOption in $deliveryOptions) {
            $currentTemplate = $deliveryOption.Details.DeploymentTemplateDeliveryOptionDetails.Template
            # Find matching template name or default to first
            $matchingTemplate = $templateNames | Where-Object { $currentTemplate -like "*$_" }
            $templateName = if ($matchingTemplate) { $matchingTemplate } else { $templateNames[0] }
            $newTemplateUrl = "${baseS3Url}${templateName}"

            $deliveryOptionsUpdates += @{
                Id = $deliveryOption.Id
                Details = @{
                    DeploymentTemplateDeliveryOptionDetails = @{
                        Template = $newTemplateUrl
                        # Preserve other fields as needed
                    }
                }
            }
        }

        $detailsDocument = @{
            DeliveryOptions = $deliveryOptionsUpdates
            Version = @{
                ReleaseNotes = "Updated CloudFormation templates to version $Version on $(Get-Date -Format 'yyyy-MM-dd')"
            }
        }

        $detailsJson = $detailsDocument | ConvertTo-Json -Depth 10 -Compress

        # Step 5: Create the Change object
        $change = New-Object Amazon.MarketplaceCatalog.Model.Change
        $change.ChangeType = 'UpdateDeliveryOptions'
        $change.Entity = New-Object Amazon.MarketplaceCatalog.Model.Entity
        $change.Entity.Type = 'AmiProduct@1.0'
        $change.Entity.Identifier = $versionIdentifier
        $change.Details = $detailsJson

        # Step 6: Start the ChangeSet
        $clientToken = [guid]::NewGuid().ToString()
        $changeSetResponse = Start-MCATChangeSet -Catalog 'AWSMarketplace' -ChangeSet @($change) -ClientRequestToken $clientToken -ChangeSetName "UpdateTemplates-$productId-$Version-$(Get-Date -Format 'yyyyMMddHHmmss')"

        Write-Host "ChangeSet started for product $($productId): ID = $($changeSetResponse.ChangeSetId), ARN = $($changeSetResponse.ChangeSetArn)"

        # Step 7: Poll for ChangeSet status
        $status = 'PREPARING'
        while ($status -eq 'PREPARING' -or $status -eq 'APPLYING') {
            Start-Sleep -Seconds 10
            $changeSetStatus = Get-MCATChangeSet -Catalog 'AWSMarketplace' -ChangeSetId $changeSetResponse.ChangeSetId
            $status = $changeSetStatus.Status
            Write-Host "Current status for product $($productId): $status"
        }

        if ($status -eq 'SUCCEEDED') {
            Write-Host "Template update succeeded for product $productId."
        } elseif ($status -eq 'FAILED') {
            Write-Error "Template update failed for product $productId. Failure reason: $($changeSetStatus.FailureDescription)"
            exit 1
        } else {
            Write-Error "Unexpected status for product $($productId): $status"
            exit 1
        }
    }

    Write-Host "All products updated successfully."
} catch {
    Write-Error "Error: $_"
    exit 1
}