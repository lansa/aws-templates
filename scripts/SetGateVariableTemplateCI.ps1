param (
    [Parameter(Mandatory=$true)]
    [string]
    $BaseImageName,

    [Parameter(Mandatory=$true)]
    [string]
    $stackname,

    [Parameter(Mandatory=$true)]
    [string]
    $Version

   )

# #SetGateVariable.ps1 -BaseImageName w12r2d-14-2 -stackname BakingDP-ImageRelease
# # Set the Gate variable if the file exists
Write-Host "##vso[task.setvariable variable=IsEnabled;isOutput=true]False"
$path = "$($env:Pipeline_Workspace)/_Build Image Release Artefacts/aws/$BaseImageName.txt"
Write-Host "Using $path"
if (Test-Path $path) {
    try{
        $amiID = Get-Content -Path $path
        $amiID = $amiID.Split(" ")[0]   
        Write-Host "AMI ID $($amiID)"
        $imageName = (Get-EC2Image -ImageId $amiID).Name
        $imageName -match "$BaseImageName[-]?[0-9]+"
        $VersionLocal = $Matches[0]
        $VersionLocal = $VersionLocal -replace "-\d+$"  # Removes the last elements from the string . This will be replaced with 7 in the next step.
        $VersionLocal = "$VersionLocal-$Version"
        Write-Host "Version: $VersionLocal"
        $stackname = "$stackname-$BaseImageName"
        Write-Host "Stack name : $stackname"
        #Set Variables
        Write-Host "##vso[task.setvariable variable=stack;isOutput=true]$stackname"
        Write-Host "##vso[task.setvariable variable=version;isOutput=true]$VersionLocal"
        Write-Host "##vso[task.setvariable variable=ImageID;isOutput=true]$amiID"
        Write-Host "##vso[task.setvariable variable=IsEnabled;isOutput=true]True"
        Write-host "The value of Variable IsEnabled is updated to True and output variable ImageID to $amiID"
    } catch{
        $_ | Out-Default | Write-Host
        Throw "Failed to set Task Variable"
    }
} else {
    Write-Host "Artifact path does NOT exist for $BaseImageName"
}
