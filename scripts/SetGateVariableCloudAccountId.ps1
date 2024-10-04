param (
    [Parameter(Mandatory=$true)]
    [string]
    $BaseImageName,

    [Parameter(Mandatory=$true)]
    [string]
    $stackname
   )

#SetGateVariable.ps1 -BaseImageName w12r2d-14-2 -stackname BakingDP-ImageRelease
# Set the Gate variable if the file exists
Write-Host "##vso[task.setvariable variable=IsEnabled;isOutput=true]False"
#$path = "$($env:System_DefaultWorkingDirectory)/_Build Cloud Account Id Artefacts  3.0/aws/$BaseImageName.txt"
$path = "$($env:Pipeline_Workspace)/_Build Cloud Account Id Artefacts/aws/$BaseImageName.txt"
Write-Host "Using $path"
if (Test-Path $path) {
    try{
        $amiID = Get-Content -Path $path
        $amiID = $amiID.Split(" ")[0]
        Write-Host "AMI ID $($amiID)"
        $stackname = "$stackname"
        Write-Host "Stack name : $stackname"
        #Set Variables
        Write-Host "##vso[task.setvariable variable=stack;isOutput=true]$stackname"
        Write-Host "##vso[task.setvariable variable=ImageID;isOutput=true]$amiID"
        Write-Host "##vso[task.setvariable variable=IsEnabled;isOutput=true]True"
        Write-host "The value of Variable IsEnabled is updated to True and output variable ImageID to $amiID"
    } catch{
        $_ | Out-Default | Write-Host
        Throw "Failed to set Task Variable"
    }
} else {
    throw "Artifact path does NOT exist for $BaseImageName" # Throwing error if there's no baseimage, instead of just writing it to the host.
}
