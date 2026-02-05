# UpdateTemplatesInMarketplace.ps1
# This script queries all the artefacts published by Build Image Release Artefacts pipeline
# It automatically works out which Marketplace Products to update based on the artefacts available.
#
# This script updates or adds a version for AWS Marketplace AMI-based products, updating AMI IDs and CloudFormation template URLs.
# Templates are only updated when adding a new version; existing versions issue a warning.
# It uses AWS PowerShell cmdlets to describe products, identify versions, and submit change sets.
# Assumptions:
# - AWS PowerShell module is installed (e.g., AWS.Tools.MarketplaceCatalog).
# - Credentials are set via environment variables or default profile.
# - Runs in Azure DevOps self-hosted Windows agent context.
# - Compatible with PowerShell 5.1.

param (
    [Parameter(Mandatory=$true)]
    [string]$VersionDigits = "21"
)

function UpdateMarketplaceProduct{
    param (
        [Parameter(Mandatory=$true)]
        [string]$Version = "15.0.22",
        [Parameter(Mandatory=$true)]
        [string]$buildName = "w19d-15-0",
        [Parameter(Mandatory=$true)]
        [string]$amiId = "ami-079801eb19b89d0baxxx"
    )

    # Hardcoded mapping of base names to product IDs
    # Note this table is also in Cookbooks/scripts/SetMarketplaceVariables.ps1
    # Keep both copies in sync
    $productMapping = @(
        @('w19d-15-0', 'prod-7c4xdvxkskdfs'),  # English
        @('w19d-15-0j', 'prod-csfkcd5qvncle'),   # Japanese
        @('w19d-16-0', 'prod-7c4xdvxkskdfs'),  # English
        @('w19d-16-0j', 'prod-csfkcd5qvncle'),   # Japanese

        @('w22d-15-0', 'prod-vmu3flp7pyc4a'),  # English
        @('w22d-15-0j', 'prod-uxdxgg354h7aq'),   # Japanese
        @('w22d-16-0', 'prod-vmu3flp7pyc4a'),  # English
        @('w22d-16-0j', 'prod-uxdxgg354h7aq'),   # Japanese

        @('w25d-15-0', 'prod-gquyjeiww36se'),  # English
        @('w25d-15-0j', 'prod-urhng7afyfwr6'),   # Japanese
        @('w25d-16-0', 'prod-gquyjeiww36se'),  # English
        @('w25d-16-0j', 'prod-urhng7afyfwr6')   # Japanese
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
        $mapping = $productMapping | Where-Object { $_[0] -eq $buildName }
        if (-not $mapping) {
            throw "No product ID found for base name $buildName"
        }
        $productId = $mapping[1]
        Write-Host "Processing product: $productId (BaseName: $buildName, AMI ID: $amiId)"

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
            # ***********************************************************************
            return $False # Don't fail the pipeline, just exit successfully. The DevOps variable manualMPUpdateRequired is tested in the pipeline to determine if a manual update is required.
            # ***********************************************************************

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
        Write-Host "Delivery Options for version $($versionDetails.VersionTitle) in product $productId :"
        $versionDetails.DeliveryOptions | ForEach-Object { Write-Host "Delivery Option: $_" }
        $deliveryOptions = $versionDetails.DeliveryOptions
        if (-not $deliveryOptions) {
            throw "No delivery options found in version $($versionDetails.VersionTitle) for product $productId"
        }
        Write-Host "Found $(($deliveryOptions | Measure-Object).Count) delivery options"
        $deliveryOptions | ForEach-Object { Write-Host "Delivery Option ID: $($_.Id), Source ID: $($_.SourceId)" }
        $deliveryOptions | Out-Default | Write-Host

        # Step 4: Construct the DetailsDocument
        if ($changeType -eq 'UpdateDeliveryOptions') {
            $deliveryOptionsUpdates = @()
            foreach ($templateName in $templateNames) {
                $cftDeliveryOption = $versionDetails.DeliveryOptions | Where-Object { $_.Type -eq 'CloudFormationTemplate' -and $_.SourceId -in ($versionDetails.Sources | Where-Object { $_.Template -like "*$templateName" }).Id } | Select-Object -First 1
                if ($cftDeliveryOption) {
                    Write-Host "Processing CloudFormation Delivery Option ID: $($cftDeliveryOption.Id), Source ID: $($cftDeliveryOption.SourceId)"
                    $source = $versionDetails.Sources | Where-Object { $_.Id -eq $cftDeliveryOption.SourceId }
                    if (-not $source) {
                        Write-Warning "No source found for template $templateName in version $($versionDetails.VersionTitle) for product $productId. Skipping."
                        continue
                    }
                    $amiSource = @{
                        AmiId = $amiId
                        AccessRoleArn = $iamRoleArn
                    }
                    $details = @{
                        DeploymentTemplateDeliveryOptionDetails = @{
                            TemplateSources = @(
                                @{
                                    ParameterName = $source.SourceParameters.ParameterName
                                    SourceId = $source.SourceParameters.SourceId
                                    AmiSource = $amiSource
                                }
                            )
                        }
                    }
                    $deliveryOptionsUpdates += @{
                        Id = $cftDeliveryOption.Id
                        Details = $details
                    }
                } else {
                    Write-Warning "No CloudFormation delivery option found for template $templateName in product $productId. Skipping."
                }
            }
            if ($deliveryOptionsUpdates.Count -eq 0) {
                Write-Warning "No CloudFormation delivery options to update for product $productId. Skipping ChangeSet submission."
                continue
            }
            $detailsDocument = @{
                Version = @{
                    ReleaseNotes = "Updated CloudFormation template sources for version $Version on $(Get-Date -Format 'yyyy-MM-dd')"
                }
                DeliveryOptions = $deliveryOptionsUpdates
            }
        } else {
            # AddDeliveryOptions: Create full DeliveryOptions array (unchanged)
            $deliveryOptionsUpdates = @()
            # First, locate AmiSource details
            $amiSource = $null
            foreach ($deliveryOption in $versionDetails.DeliveryOptions) {
                if ($deliveryOption.Type -eq 'AmazonMachineImage') {
                    $amiSourceSource = $versionDetails.Sources | Where-Object { $_.Id -eq $deliveryOption.SourceId }
                    if ($amiSourceSource) {
                        if (-not $amiSourceSource.OperatingSystem.Name -or -not $amiSourceSource.OperatingSystem.Version) {
                            throw "Missing OperatingSystemName or OperatingSystemVersion for AMI source in product $productId"
                        }
                        $amiSource = @{
                            AmiId = $amiId
                            AccessRoleArn = $iamRoleArn
                            UserName = $amiSourceSource.OperatingSystem.Username
                            OperatingSystemName = $amiSourceSource.OperatingSystem.Name
                            OperatingSystemVersion = $amiSourceSource.OperatingSystem.Version
                            ScanningPort = $amiSourceSource.OperatingSystem.ScanningPort
                        }
                        break
                    }
                }
            }
            if (-not $amiSource) {
                throw "No AMI source details found for product $productId"
            }

            # Add AMI delivery option
            $amiDeliveryOption = $versionDetails.DeliveryOptions | Where-Object { $_.Type -eq 'AmazonMachineImage' } | Select-Object -First 1
            if ($amiDeliveryOption) {
                if (-not $amiDeliveryOption.Recommendations -or -not $amiDeliveryOption.Recommendations.SecurityGroups) {
                    throw "No SecurityGroups found in Recommendations for AMI delivery option in product $productId"
                }
                $securityGroups = @()
                foreach ($sg in $amiDeliveryOption.Recommendations.SecurityGroups) {
                    if (-not $sg.Protocol -or -not $sg.CidrIps -or -not $sg.FromPort -or -not $sg.ToPort) {
                        throw "Missing required SecurityGroups properties (Protocol, CidrIps, FromPort, ToPort) for AMI delivery option in product $productId"
                    }
                    $ipRanges = @()
                    $ipRanges += $sg.CidrIps
                    $securityGroups += @{
                        IpProtocol = $sg.Protocol
                        IpRanges = $ipRanges
                        FromPort = $sg.FromPort
                        ToPort = $sg.ToPort
                    }
                }
                $details = @{
                    DeliveryOptionTitle = if ($amiDeliveryOption.Title) { $amiDeliveryOption.Title } else { "AMI Delivery Option" }
                    Details = @{
                        AmiDeliveryOptionDetails = @{
                            AmiSource = $amiSource
                            UsageInstructions = $amiDeliveryOption.Instructions.Usage
                            RecommendedInstanceType = $amiDeliveryOption.Recommendations.InstanceType
                            SecurityGroups = $securityGroups
                        }
                    }
                }
                $deliveryOptionsUpdates += $details
            } else {
                throw "No AMI delivery option found for product $productId"
            }

            # Add CFT delivery options for each template
            foreach ($templateName in $templateNames) {
                $cftDeliveryOption = $versionDetails.DeliveryOptions | Where-Object { $_.Type -eq 'CloudFormationTemplate' -and $_.SourceId -in ($versionDetails.Sources | Where-Object { $_.Template -like "*$templateName" }).Id } | Select-Object -First 1
                if ($cftDeliveryOption) {
                    $source = $versionDetails.Sources | Where-Object { $_.Id -eq $cftDeliveryOption.SourceId }
                    if (-not $source) {
                        throw "No source found for template $templateName in version $($versionDetails.VersionTitle)"
                    }
                    $newTemplateUrl = "${baseS3Url}${templateName}"
                    Write-Host "Adding CFT Delivery Option: Template=$newTemplateUrl"
                    $details = @{
                        DeliveryOptionTitle = if ($cftDeliveryOption.Title) { $cftDeliveryOption.Title } else { "CFT Delivery Option: $templateName" }
                        Details = @{
                            DeploymentTemplateDeliveryOptionDetails = @{
                                Template = $newTemplateUrl
                                ShortDescription = $cftDeliveryOption.ShortDescription
                                LongDescription = $cftDeliveryOption.LongDescription
                                UsageInstructions = $cftDeliveryOption.Instructions.Usage
                                RecommendedInstanceType = $cftDeliveryOption.Recommendations.InstanceType
                                ArchitectureDiagram = $source.ArchitectureDiagram
                                TemplateSources = @(
                                    @{
                                        ParameterName = $source.SourceParameters.ParameterName
                                        SourceId = $source.SourceParameters.SourceId
                                        AmiSource = $amiSource
                                    }
                                )
                            }
                        }
                    }
                    $deliveryOptionsUpdates += $details
                }
            }

            $detailsDocument = @{
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
        Write-Host "ChangeSet started for product $productId : ID = $($changeSetResponse.ChangeSetId), ARN = $($changeSetResponse.ChangeSetArn)"

        # Collect ChangeSet response for later polling
        $global:changeSetResponses += @{
            ChangeSetResponse = $changeSetResponse
            ProductId = $productId
            ChangeType = $changeType
            Status = $null
            FailureDescription = $null
        }

        return $True
    } catch {
        Write-Error "Error: $_"
        throw
    }
}

# Main script logic
Write-Host "##vso[task.setvariable variable=MarketPlaceUpdateInterventionRequired;isOutput=true]True"

# Initialize array to collect ChangeSet responses
$global:changeSetResponses = @()

$path = "$($env:Pipeline_Workspace)\templates\support\scalable\ami-list"
if (-not (Test-Path $path)) {
    $path = 'C:\temp\aws\amilist'  # Use this for debugging
}

Write-Host "Using $path"
if (Test-Path $path) {
    try{
        Write-Host("Locate any files in the path $path")
        # Get all .txt files matching the pattern w??d-??-?*.txt
        # Sort them with the oldest windows version and lansa version first e.g. w22d... is before w25d...
        # and 15.0.xx is before 16.0.xx.
        # This ensures that when published the Product shows the latest version FIRST in the list
        # with the version appearing as e.g. "16.0.22 (latest version)", with 15.0.22 below it
        # and hidden until clicking on the drop down.
        # This is because the LAST version added to a Product is the latest version. Its not about the numbering.
        $files = Get-ChildItem -Path $path -Filter "*.txt" |
            Where-Object { $_.BaseName -match '^w\d{2}d-\d{2}-\d{1}.*$' } | Sort-Object -Property Name
        if ($files.Count -eq 0) {
            throw "No matching AMI files found in path $path"
        }
        Write-Host "Found $($files.Count) matching AMI files:"
        $files | ForEach-Object { Write-Host " - $($_.FullName)" }

        $productVersions = @()
        foreach ($file in $files ) {
            $buildName = $file.BaseName  # e.g., "w19d-15-0"
            $parts = $buildName.Split('-')
            $isJapanese = $file.BaseName -match '.*j$'
            $versionBase = $parts[1]  # e.g., 15
            $versionMinor = $parts[2].Replace('j', '')  # e.g., 0, removing 'j' if present

            $entry = [PSCustomObject]@{
                buildName = $buildName
                productId =  if ($isJapanese) { $($file.BaseName).Substring(0, 4) + 'j' } else { $($file.BaseName).Substring(0, 4) } # e.g., "w19d"
                isJapanese = $isJapanese
                versionBase = $versionBase
                versionMinor = $versionMinor
                version = "$versionBase.$versionMinor.$VersionDigits"  # e.g., "15.0.21"
                amiId = (Get-Content $file.FullName).Trim()
            }
            $productVersions += $entry
        }
        $updatesByProduct = $productVersions | Group-Object ProductId
        # presume there are the same number of versions per product
        $VersionCount = $updatesByProduct.Group.Count
        for ($VersionNumber = 0; $VersionNumber -lt $VersionCount; $VersionNumber++) {
            Write-Host "Updating Marketplace Products for Version $($updatesByProduct.Group[$VersionNumber].version)..."

            foreach ($ProductIdGroup in $updatesByProduct) {
                if ( $null -eq $ProductIdGroup.Group[$VersionNumber]) {
                    Write-Warning "No entry found for ProductId $($ProductIdGroup.Name) at index $VersionNumber. Skipping."
                    continue
                }
                Write-Host "ProductId: $($ProductIdGroup.Name)"
                $buildName = $ProductIdGroup.Group[$VersionNumber].buildName
                $version = $ProductIdGroup.Group[$VersionNumber].version
                $amiId = $ProductIdGroup.Group[$VersionNumber].amiId

                Write-Host "Processing ProductId: $($ProductIdGroup.Name), BuildName: $buildName, Version: $version, Ami ID: $amiId"
                if (UpdateMarketplaceProduct -Version $version -buildName $buildName -amiId $amiId) {
                    Write-Host "ChangeSet submitted successfully for product $($ProductIdGroup.Name) to version $version."
                } else {
                    Write-Host "ChangeSet skipped for product $($ProductIdGroup.Name) to version $version."
                }
            }

            # Step 7: Poll for ChangeSet status for all collected responses and store results
            Write-Host "Polling status for all submitted ChangeSets..."
            if ($changeSetResponses.Count -eq 0) {
                Write-Host "No ChangeSets were submitted. Exiting."
                Write-Host "##vso[task.setvariable variable=MarketPlaceUpdateInterventionRequired;isOutput=true]False"
                continue # Next version
            }

            foreach ($response in $changeSetResponses) {
                $changeSetResponse = $response.ChangeSetResponse
                $productId = $response.ProductId
                $response.Status = 'PREPARING'
                Write-Host "Checking status for product $productId, ChangeSet ID: $($changeSetResponse.ChangeSetId)"
                while ($response.Status -eq 'PREPARING' -or $response.Status -eq 'APPLYING') {
                    Start-Sleep -Seconds 60 # Wait for 60 seconds before polling again
                    $changeSetStatus = Get-MCATChangeSet -Catalog 'AWSMarketplace' -ChangeSetId $changeSetResponse.ChangeSetId
                    $response.Status = $changeSetStatus.Status
                    $response.FailureDescription = $changeSetStatus.FailureDescription
                    Write-Host "Current status for product $productId : $($response.Status)"
                }
                Write-Host "Final status for product $productId : $($response.Status)"
                if ($response.Status -eq 'SUCCEEDED') {
                    Write-Host "Update succeeded for product $productId."
                } elseif ($response.Status -eq 'FAILED') {
                    Write-Error "Update failed for product $productId. Failure reason: $($response.FailureDescription)"
                } else {
                    Write-Error "Unexpected status for product $productId : $($response.Status)"
                }
            }

            # Display summary of all ChangeSet statuses
            Write-Host "`n=== ChangeSet Status Summary ==="
            Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') AEST"
            foreach ($response in $changeSetResponses) {
                Write-Host "ProductId: $($response.ProductId), ChangeSetId: $($response.ChangeSetResponse.ChangeSetId), ChangeType: $($response.ChangeType)"
                Write-Host "Status: $($response.Status)"
                $errorDetails = if ($response.FailureDescription -and $response.ChangeSetResponse.ChangeSetId) {
                    $changeSetStatus = Get-MCATChangeSet -Catalog 'AWSMarketplace' -ChangeSetId $response.ChangeSetResponse.ChangeSetId
                    if ($changeSetStatus.ChangeSet[0].ErrorDetailList) {
                        $changeSetStatus.ChangeSet[0].ErrorDetailList
                    } else {
                        @([PSCustomObject]@{ ErrorCode = 'N/A'; ErrorMessage = $response.FailureDescription })
                    }
                } else {
                    @([PSCustomObject]@{ ErrorCode = 'N/A'; ErrorMessage = 'N/A' })
                }
                Write-Host "ErrorDetailList:"
                foreach ($errorDetail in $errorDetails) {
                    Write-Host "  [$($errorDetail.ErrorCode)] $($errorDetail.ErrorMessage)"
                }
                Write-Host "---"
            }
            Write-Host "=== End of Summary ==="

            # Check for failed ChangeSets and throw after summary
            $failedChangeSets = $changeSetResponses | Where-Object { $_.Status -eq 'FAILED' }
            if ($failedChangeSets) {
                throw "One or more ChangeSets failed. See above for details"
            }
        }
    } catch{
        $_ | Out-Default | Write-Host
        Throw "Failed to add MP Version"
    }


    Write-Host "##vso[task.setvariable variable=MarketPlaceUpdateInterventionRequired;isOutput=true]False"
    Write-Host "All products processed successfully."
} else {
    Throw "Artifact path $path does NOT exist"
}