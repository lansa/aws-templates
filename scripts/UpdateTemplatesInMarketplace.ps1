# UpdateMarketplaceTemplates.ps1
# This script updates or adds version 15.0.20 for AWS Marketplace AMI-based products, focusing on updating CloudFormation template URLs.
# It uses AWS PowerShell cmdlets to describe products, add template artifacts, and update/add delivery options.
# Assumptions:
# - AWS PowerShell module is installed (e.g., AWS.Tools.MarketplaceCatalog).
# - Credentials are set via environment variables or default profile.
# - Runs in Azure DevOps self-hosted Windows agent context.
# - Compatible with PowerShell 5.1.

param (
    [Parameter(Mandatory=$false)]
    [string]$Version = "15.0.20",
    [Parameter(Mandatory=$false)]
    [array]$amiList = @(
        @('w19d_15_0', 'ami-050c4e7c670bd83dd'),  # English
        @('w19d_15_0j', 'ami-0b8c391f2f8bbd47d')   # Japanese
    )
)

# Hardcoded mapping of base names to product IDs
$productMapping = @(
    @('w19d_15_0', 'prod-pgisjel5bhxsi'),  # English
    @('w19d_15_0j', 'prod-csfkcd5qvnclexxxx')   # Japanese

    #@('w19d_15_0', 'prod-7c4xdvxkskdfs'),  # English
    #@('w19d_15_0j', 'prod-csfkcd5qvncle')   # Japanese
)

# Template names (same for all products)
$templateNames = @(
    'lansa-stack-type-win.cfn.template',
    'lansa-master-win.cfn.template'
)

# Base S3 URL for templates
$baseS3Url = "https://lansa.s3.ap-southeast-2.amazonaws.com/templates/support/scalable/"

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
            Write-Error "No product ID found for base name $baseName"
            continue
        }
        $productId = $mapping[1]
        Write-Host "Processing product: $($productId) (BaseName: $baseName, AMI ID: $amiId)"

        # Step 1: Describe the product entity to get version details
        $entityResponse = Get-MCATEntity -Catalog 'AWSMarketplace' -EntityId $productId
        if (-not $entityResponse) {
            Write-Error "Failed to retrieve entity for product $($productId)"
            continue
        }
        $entityResponse | Out-Default | Write-Host

        $productDetails = $entityResponse.Details | ConvertFrom-Json
        if (-not $productDetails) {
            Write-Error "Failed to parse details for product $($productId)"
            continue
        }
        $productDetails | Format-List | Out-Default | Write-Host

        # Step 2: Find the target version or prepare to add delivery options
        if ($productDetails.Versions.Count -eq 0) {
            Write-Error "No versions found for product $($productId)"
            continue
        }
        Write-Host "Available versions for product $($productId):"
        $productDetails.Versions | ForEach-Object { Write-Host "Version: $($_.VersionTitle) (ID: $($_.Id), CreationDate: $($_.CreationDate))" }
        $targetVersion = $productDetails.Versions | Where-Object { $_.VersionTitle -eq $Version }

        $changeType = $null
        $versionDetails = $null
        if ($targetVersion) {
            Write-Host "Found target version $Version for product $($productId) with ID $($targetVersion.Id)"
            $changeType = 'UpdateDeliveryOptions'
            # Fetch delivery options for the target version
            $versionDetailsResponse = Get-MCATEntity -Catalog 'AWSMarketplace' -EntityId $productId
            $versionDetails = ($versionDetailsResponse.Details | ConvertFrom-Json).Versions | Where-Object { $_.VersionTitle -eq $Version }
            if (-not $versionDetails) {
                Write-Error "Failed to retrieve delivery options for version $Version in product $($productId)"
                continue
            }
            Write-Host "Target version details for $Version in product $($productId):"
            $versionDetails | Format-List | Out-Default | Write-Host
        } else {
            Write-Host "Version $Version not found for product $($productId). Adding new delivery options."
            $changeType = 'AddDeliveryOptions'
            # Fetch all details of the latest version
            $latestVersion = $productDetails.Versions | Sort-Object CreationDate -Descending | Select-Object -First 1
            $latestVersionResponse = Get-MCATEntity -Catalog 'AWSMarketplace' -EntityId $productId
            $versionDetails = ($latestVersionResponse.Details | ConvertFrom-Json).Versions | Where-Object { $_.VersionTitle -eq $latestVersion.VersionTitle }
            if (-not $versionDetails) {
                Write-Error "No latest version details found for product $($productId)"
                continue
            }
            Write-Host "Copying details from latest version: $($versionDetails.VersionTitle) (ID: $($versionDetails.Id))"
            $versionDetails | Format-List | Out-Default | Write-Host
        }

        # Step 3: Get delivery options
        if (-not $versionDetails.DeliveryOptions) {
            Write-Error "No delivery options found for version $($versionDetails.VersionTitle) in product $($productId)"
            continue
        }
        Write-Host "Delivery Options for version $($versionDetails.VersionTitle) in product $($productId):"
        $versionDetails.DeliveryOptions | ForEach-Object { Write-Host "Delivery Option: $_" }
        $deliveryOptions = $versionDetails.DeliveryOptions
        if (-not $deliveryOptions) {
            Write-Error "No delivery options found in version $($versionDetails.VersionTitle) for product $($productId)"
            continue
        }
        Write-Host "Found $(($deliveryOptions | Measure-Object).Count) delivery options"
        $deliveryOptions | ForEach-Object { Write-Host "Delivery Option ID: $($_.Id), Source ID: $($_.SourceId)" }
        $deliveryOptions | Format-List | Out-Default | Write-Host

        # Step 4: Construct the ChangeSet with AddResource and Delivery Option changes
        $changeSet = @()
        foreach ($deliveryOption in $versionDetails.DeliveryOptions) {
            Write-Host "Processing Delivery Option ID: $($deliveryOption.Id), Source ID: $($deliveryOption.SourceId)"
            if ($deliveryOption.Type -eq 'AmazonMachineImage') {
                continue
                # Find the source matching the delivery option's SourceId
                $source = $versionDetails.Sources | Where-Object { $_.Id -eq $deliveryOption.SourceId }
                if (-not $source) {
                    Write-Error "No source found for SourceId $($deliveryOption.SourceId) in version $($versionDetails.VersionTitle)"
                    exit 1
                }
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
                            }
                            UsageInstructions = $deliveryOption.Instructions.Usage
                            RecommendedInstanceType = $deliveryOption.Recommendations.InstanceType
                            SecurityGroups = $deliveryOption.Recommendations.SecurityGroups
                        }
                    }
                }
            } elseif ($deliveryOption.Type -eq 'CloudFormationTemplate') {
                # Find the source matching the delivery option's SourceId
                $source = $versionDetails.Sources | Where-Object { $_.Id -eq $deliveryOption.SourceId }
                if (-not $source) {
                    Write-Error "No source found for SourceId $($deliveryOption.SourceId) in version $($versionDetails.VersionTitle)"
                    exit 1
                }
                $currentTemplate = $source.Template
                $matchingTemplate = $templateNames | Where-Object { $currentTemplate -like "*$_" }
                if (-not $matchingTemplate) {
                    Write-Error "No matching template found for current template URL $currentTemplate in version $($versionDetails.VersionTitle)"
                    exit 1
                }
                $templateName = $matchingTemplate
                $newTemplateUrl = "${baseS3Url}${templateName}"
                Write-Host "Matching Template: $templateName"
                Write-Host "New Template URL: $newTemplateUrl"
                Write-Host "SourceParameters: ParameterName=$($source.SourceParameters.ParameterName), SourceId=$($source.SourceParameters.SourceId)"

                # Create unique artifact ID for the new template
                $artifactId = "artifact-$($deliveryOption.Id)-$(Get-Date -Format 'yyyyMMddHHmmss')"
                $artifactChange = @{
                    ChangeType = "AddResource"
                    Entity = @{
                        Type = "CLOUDFORMATION_TEMPLATE"
                    }
                    Details = @{
                        Name = $templateName
                        Description = "CloudFormation template for $productId version $Version"
                        Source = @{
                            S3Url = $newTemplateUrl
                        }
                    } | ConvertTo-Json -Compress -Depth 5
                    Id = $artifactId
                }
                $changeSet += $artifactChange

                # Define delivery option change
                $deliveryOptionDetails = if ($changeType -eq 'UpdateDeliveryOptions') {
                    @{
                        DeploymentTemplateDeliveryOptionDetails = @{
                            ArtifactId = $artifactId
                            ArtifactType = "CLOUDFORMATION_TEMPLATE"
                        }
                    }
                } else {
                    # AddDeliveryOptions: Copy all fields
                    @{
                        DeploymentTemplateDeliveryOptionDetails = @{
                            ArtifactId = $artifactId
                            ArtifactType = "CLOUDFORMATION_TEMPLATE"
                            DeliveryOptionTitle = $deliveryOption.Title
                            ShortDescription = $deliveryOption.ShortDescription
                            LongDescription = $deliveryOption.LongDescription
                            UsageInstructions = $deliveryOption.Instructions.Usage
                            RecommendedInstanceType = $deliveryOption.Recommendations.InstanceType
                            ArchitectureDiagram = $source.ArchitectureDiagram
                            SourceParameters = @(
                                @{
                                    ParameterName = $source.SourceParameters.ParameterName
                                    SourceId = $source.SourceParameters.SourceId
                                }
                            )
                        }
                    }
                }

                $deliveryOptionChange = @{
                    ChangeType = $changeType
                    Entity = @{
                        Type = "AmiProduct@1.0"
                        Identifier = $productId
                    }
                    Details = if ($changeType -eq 'UpdateDeliveryOptions') {
                        @{
                            Version = @{
                                ReleaseNotes = "Updated CloudFormation template for version $Version on $(Get-Date -Format 'yyyy-MM-dd')"
                            }
                            DeliveryOptions = @(
                                @{
                                    Id = $deliveryOption.Id
                                    Details = $deliveryOptionDetails
                                }
                            )
                        } | ConvertTo-Json -Compress -Depth 5
                    } else {
                        @{
                            Version = @{
                                VersionTitle = $Version
                                ReleaseNotes = "Added version $Version with updated CloudFormation template on $(Get-Date -Format 'yyyy-MM-dd')"
                            }
                            DeliveryOptions = @(
                                @{
                                    Id = $deliveryOption.Id
                                    Details = $deliveryOptionDetails
                                }
                            )
                        } | ConvertTo-Json -Compress -Depth 5
                    }
                }
                $changeSet += $deliveryOptionChange
            } else {
                Write-Error "Unsupported delivery option type: $($deliveryOption.Type)"
                continue
            }
        }

        # Step 5: Start the ChangeSet
        $clientToken = [guid]::NewGuid().ToString()
        if ($changeType -eq 'AddDeliveryOptions') {
            $changeSetResponse = Start-MCATChangeSet -Catalog 'AWSMarketplace' -ChangeSet $changeSet -ClientRequestToken $clientToken -ChangeSetName "ValidateNewRevision-$productId-$Version-$(Get-Date -Format 'yyyyMMddHHmmss')" -Intent 'Validate'
        } else {
            $changeSetResponse = Start-MCATChangeSet -Catalog 'AWSMarketplace' -ChangeSet $changeSet -ClientRequestToken $clientToken -ChangeSetName "UpdateDeliveryOptions-$productId-$Version-$(Get-Date -Format 'yyyyMMddHHmmss')"
        }
        Write-Host "ChangeSet started for product $($productId): ID = $($changeSetResponse.ChangeSetId), ARN = $($changeSetResponse.ChangeSetArn)"

        # Step 6: Poll for ChangeSet status
        $status = 'PREPARING'
        while ($status -eq 'PREPARING' -or $status -eq 'APPLYING') {
            Start-Sleep -Seconds 10
            $changeSetStatus = Get-MCATChangeSet -Catalog 'AWSMarketplace' -ChangeSetId $changeSetResponse.ChangeSetId
            $status = $changeSetStatus.Status
            Write-Host "Current status for product $($productId): $status"
        }

        if ($status -eq 'SUCCEEDED') {
            Write-Host "Template update succeeded for product $($productId)."
        } elseif ($status -eq 'FAILED') {
            Write-Error "Template update failed for product $($productId). Failure reason: $($changeSetStatus.FailureDescription)"
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