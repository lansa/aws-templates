#e.g CopyAMIToUS.ps1 -BaseImageName w12r2d-14-2
param (
    [Parameter(Mandatory=$true)]
    [string]
    $BaseImageName
)

Write-Host "##vso[task.setvariable variable=Exists;isOutput=true]False"
#$path = "$($env:System_DefaultWorkingDirectory)/_Build Cloud Account Id Artefacts/aws/$BaseImageName.txt"
$path = "$($env:Pipeline_Workspace)/_Build Cloud Account Id Artefacts/aws/$BaseImageName.txt"
Write-Host "Using $path"
if (Test-Path $path) {
    try{
        $amiID = Get-Content -Path $path
        Write-Host "AMI ID = $amiID"
        $imageName = (Get-EC2Image -ImageId $amiID).Name
        Write-Host "Image Copy takes a few minutes"
        $imageID = Copy-EC2Image -SourceRegion ap-southeast-2 -SourceImageId $amiID -Region us-east-1 -Name $imageName
        Write-Host "imageID: $imageID"
        Write-Host "##vso[task.setvariable variable=Exists;isOutput=true]True"
        Write-Host "##vso[task.setvariable variable=name;isOutput=true]$imageName"
        Write-Host "##vso[task.setvariable variable=id;isOutput=true]$imageID"
    } catch{
        $_ | Out-Default | Write-Host
        Throw "Failed to set Task Variable"
    }
} else {
    Write-Host "##vso[task.setvariable variable=Exists;isOutput=true]False"
    Write-Host "Path does not exist"
}
