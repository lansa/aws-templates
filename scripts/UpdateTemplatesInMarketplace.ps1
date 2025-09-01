# UpdateMarketplaceTemplates.ps1
# This script updates or adds a version for AWS Marketplace AMI-based products, updating AMI IDs and CloudFormation template URLs.
# Templates are only updated when adding a new version; existing versions issue a warning.
# It uses AWS PowerShell cmdlets to describe products, identify versions, and submit change sets.
# Assumptions:
# - AWS PowerShell module is installed (e.g., AWS.Tools.MarketplaceCatalog).
# - Credentials are set via environment variables or default profile.
# - Runs in Azure DevOps self-hosted Windows agent context.
# - Compatible with PowerShell 5.1.

param (
    [Parameter(Mandatory=$false)]
    [string]$Version = "15.0.21",
    [Parameter(Mandatory=$false)]
    [array]$amiList = @(
        @('w19d-15-0', 'ami-079801eb19b89d0ba'),  # English
        @('w19d-15-0j', 'ami-0b8c391f2f8bbxxxx')   # Japanese
    )
)

# Hardcoded mapping of base names to product IDs
$productMapping = @(
    @('w19d-15-0', 'prod-pgisjel5bhxsi'),  # English
    @('w19d-15-0j', 'prod-csfkcd5qvncle')   # Japanese

    # @('w19d-15-0', 'prod-7c4xdvxkskdfs'),  # English
    # @('w19d-15-0j', 'prod-csfkcd5qvncle')   # Japanese
)

# Template names (same for all products)
$templateNames = @(
    'lansa-stack-type-win.cfn.template',
    'lansa-master-win.cfn.template'
)

# Base S3 URL for templates
$baseS3Url = "https://lansa.s3.ap-southeast-2.amazonaws.com/templates/support/scalable/"

# IAM Role ARN for AMI access
$iamRoleArn = "arn:aws:iam::775488040364:role/AWS-Marketplace-Ingestion"

# Import required modules
# Import-Module AWS.Tools.Common
# Import-Module AWS.Tools.MarketplaceCatalog

# Set default region for Marketplace Catalog API
Set-DefaultAWSRegion -Region 'us-east-1'

try {
    foreach ($amiEntry in $amiList) {
        $baseName = $amiEntry[0]
        $amiId = $amiEntry[1]
        $mapping = $productMapping | Where-Object { $_[0] -eq $baseName }
        if (-not $mapping) {
            throw "No product ID found for base name $baseName"
        }
        $productId = $mapping[1]
        Write-Host "Processing product: $productId (BaseName: $baseName, AMI ID: $amiId)"

        # Step 1: Describe the product entity to get version details
        $entityResponse = Get-MCATEntity -Catalog 'AWSMarketplace' -EntityId $productId
        if (-not $entityResponse) {
            throw "Failed to retrieve entity for product $productId"
        }
        $entityResponse | Out-String | Write-Host

        $productDetails = $entityResponse.Details | ConvertFrom-Json
        if (-not $productDetails) {
            throw "Failed to parse details for product $productId"
        }
        $productDetails | Out-Default | Write-Host

        # Step 2: Find the target version or prepare to add delivery options
        if ($productDetails.Versions.Count -eq 0) {
            throw "No versions found for product $productId"
        }
        Write-Host "Available versions for product $($productId):"
        $productDetails.Versions | ForEach-Object { Write-Host "Version: $($_.VersionTitle) (ID: $($_.Id), CreationDate: $($_.CreationDate))" }
        $targetVersion = $productDetails.Versions | Where-Object { $_.VersionTitle -eq $Version }

        $changeType = $null
        $versionDetails = $null
        if ($targetVersion) {
            Write-Warning "Version $Version already exists for product $($productId). Template updates are not allowed for existing versions. Skipping template update."
            $changeType = 'UpdateDeliveryOptions'
            # Fetch delivery options for the target version
            $versionDetailsResponse = Get-MCATEntity -Catalog 'AWSMarketplace' -EntityId $productId
            $versionDetails = ($versionDetailsResponse.Details | ConvertFrom-Json).Versions | Where-Object { $_.VersionTitle -eq $Version }
            if (-not $versionDetails) {
                throw "Failed to retrieve delivery options for version $Version in product $productId"
            }
            Write-Host "Target version details for $Version in product $($productId):"
            $versionDetails | Format-List | Out-Default | Write-Host
        } else {
            Write-Host "Version $Version not found for product $productId. Adding new delivery options."
            $changeType = 'AddDeliveryOptions'
            # Fetch all details of the latest version
            $latestVersion = $productDetails.Versions | Sort-Object CreationDate -Descending | Select-Object -First 1
            $latestVersionResponse = Get-MCATEntity -Catalog 'AWSMarketplace' -EntityId $productId
            $versionDetails = ($latestVersionResponse.Details | ConvertFrom-Json).Versions | Where-Object { $_.VersionTitle -eq $latestVersion.VersionTitle }
            if (-not $versionDetails) {
                throw "No latest version details found for product $productId"
            }
            Write-Host "Copying details from latest version: $($versionDetails.VersionTitle) (ID: $($versionDetails.Id))"
            $versionDetails | Out-Default | Write-Host
        }

        # Step 3: Get delivery options
        if (-not $versionDetails.DeliveryOptions) {
            throw "No delivery options found for version $($versionDetails.VersionTitle) in product $productId"
        }
        Write-Host "Delivery Options for version $($versionDetails.VersionTitle) in product $($productId):"
        $versionDetails.DeliveryOptions | ForEach-Object { Write-Host "Delivery Option: $_" }
        $deliveryOptions = $versionDetails.DeliveryOptions
        if (-not $deliveryOptions) {
            throw "No delivery options found in version $($versionDetails.VersionTitle) for product $productId"
        }
        Write-Host "Found $(($deliveryOptions | Measure-Object).Count) delivery options"
        $deliveryOptions | ForEach-Object { Write-Host "Delivery Option ID: $($_.Id), Source ID: $($_.SourceId)" }
        $deliveryOptions | Out-Default | Write-Host

        # Step 4: Construct the DetailsDocument
        $deliveryOptionsUpdates = @()
        foreach ($deliveryOption in $versionDetails.DeliveryOptions) {
            Write-Host "Processing Delivery Option ID: $($deliveryOption.Id), Source ID: $($deliveryOption.SourceId)"
            $details = @{}
            # Find the source matching the delivery option's SourceId
            $source = $versionDetails.Sources | Where-Object { $_.Id -eq $deliveryOption.SourceId }
            if (-not $source) {
                throw "No source found for SourceId $($deliveryOption.SourceId) in version $($versionDetails.VersionTitle)"
            }
            if ($deliveryOption.Type -eq 'AmazonMachineImage') {
                Write-Host "AMI Source: UserName=$($source.OperatingSystem.Username), OperatingSystemName=$($source.OperatingSystem.Name), OperatingSystemVersion=$($source.OperatingSystem.Version), ScanningPort=$($source.OperatingSystem.ScanningPort)"
                if ($changeType -eq 'UpdateDeliveryOptions') {
                    $details = @{
                        AmiDeliveryOptionDetails = @{
                            AmiSource = @{
                                AmiId = $amiId
                                AccessRoleArn = $iamRoleArn
                            }
                            UsageInstructions = $deliveryOption.Instructions.Usage
                        }
                    }
                } else {
                    # AddDeliveryOptions: Copy all fields
                    $details = @{
                        AmiDeliveryOptionDetails = @{
                            AmiSource = @{
                                AmiId = $amiId
                                AccessRoleArn = $iamRoleArn
                                UserName = $source.OperatingSystem.Username
                                OperatingSystemName = $source.OperatingSystem.Name
                                OperatingSystemVersion = $source.OperatingSystem.Version
                                ScanningPort = $source.OperatingSystem.ScanningPort
                            }
                            UsageInstructions = $deliveryOption.Instructions.Usage
                            RecommendedInstanceType = $deliveryOption.Recommendations.InstanceType
                            SecurityGroups = $deliveryOption.Recommendations.SecurityGroups
                        }
                    }
                }
            } elseif ($deliveryOption.Type -eq 'CloudFormationTemplate') {
                $currentTemplate = $source.Template
                $matchingTemplate = $templateNames | Where-Object { $currentTemplate -like "*$_" }
                if (-not $matchingTemplate) {
                    throw "No matching template found for current template URL $currentTemplate in version $($versionDetails.VersionTitle)"
                }
                $templateName = $matchingTemplate
                $newTemplateUrl = "${baseS3Url}${templateName}"
                Write-Host "Matching Template: $templateName"
                Write-Host "New Template URL: $newTemplateUrl"
                Write-Host "SourceParameters: ParameterName=$($source.SourceParameters.ParameterName), SourceId=$($source.SourceParameters.SourceId)"
                if ($changeType -eq 'UpdateDeliveryOptions') {
                    # Skip template update for existing versions
                    continue
                } else {
                    # AddDeliveryOptions: Include Template and all fields
                    $details = @{
                        DeploymentTemplateDeliveryOptionDetails = @{
                            Template = $newTemplateUrl
                            # DeliveryOptionTitle = $deliveryOption.Title
                            ShortDescription = $deliveryOption.ShortDescription
                            LongDescription = $deliveryOption.LongDescription
                            UsageInstructions = $deliveryOption.Instructions.Usage
                            RecommendedInstanceType = $deliveryOption.Recommendations.InstanceType
                            ArchitectureDiagram = $source.ArchitectureDiagram
                            TemplateSources = @(
                                @{
                                    ParameterName = $source.SourceParameters.ParameterName
                                    SourceId = $source.SourceParameters.SourceId
                                }
                            )
                        }
                    }
                }
            } else {
                Write-Error "Unsupported delivery option type: $($deliveryOption.Type)"
                continue
            }

            $deliveryOptionsUpdates += @{
                Id = $deliveryOption.Id
                Details = $details
            }
        }

        if ($deliveryOptionsUpdates.Count -eq 0) {
            Write-Warning "No updates to apply for product $productId. Skipping ChangeSet submission."
            continue
        }

        $detailsDocument = if ($changeType -eq 'UpdateDeliveryOptions') {
            @{
                Version = @{
                    ReleaseNotes = "Updated AMI for version $Version on $(Get-Date -Format 'yyyy-MM-dd')"
                }
                DeliveryOptions = $deliveryOptionsUpdates
            }
        } else {
            # AddDeliveryOptions: Copy all fields from latest version, update AMI and templates
            @{
                Version = @{
                    VersionTitle = $Version
                    ReleaseNotes = "Added version $Version with updated AMI and templates on $(Get-Date -Format 'yyyy-MM-dd')"
                }
                DeliveryOptions = $deliveryOptionsUpdates
            }
        }

        $detailsJson = $detailsDocument | ConvertTo-Json -Depth 10 -Compress
        Write-Host "DetailsDocument JSON: $detailsJson"

        # Step 5: Create the Change object
        $change = New-Object Amazon.MarketplaceCatalog.Model.Change
        $change.ChangeType = $changeType
        $change.Entity = New-Object Amazon.MarketplaceCatalog.Model.Entity
        $change.Entity.Type = 'AmiProduct@1.0'
        $change.Entity.Identifier = $productId
        $change.Details = $detailsJson

        # Step 6: Start the ChangeSet
        $clientToken = [guid]::NewGuid().ToString()
        if ($changeType -eq 'AddDeliveryOptions') {
            $changeSetResponse = Start-MCATChangeSet -Catalog 'AWSMarketplace' -ChangeSet @($change) -ClientRequestToken $clientToken -ChangeSetName "ValidateNewRevision-$productId-$Version-$(Get-Date -Format 'yyyyMMddHHmmss')"
        } else {
            $changeSetResponse = Start-MCATChangeSet -Catalog 'AWSMarketplace' -ChangeSet @($change) -ClientRequestToken $clientToken -ChangeSetName "UpdateDeliveryOptions-$productId-$Version-$(Get-Date -Format 'yyyyMMddHHmmss')"
        }
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
            Write-Host "Update succeeded for product $productId."
        } elseif ($status -eq 'FAILED') {
            Write-Error "Update failed for product $productId. Failure reason: $($changeSetStatus.FailureDescription)"
            throw
        } else {
            Write-Error "Unexpected status for product $($productId): $status"
            exit 1
        }
    }

    Write-Host "All products processed successfully."
} catch {
    Write-Error "Error: $_"
    throw
}