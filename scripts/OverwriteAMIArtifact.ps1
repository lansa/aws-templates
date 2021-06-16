param (
    [Parameter(Mandatory=$true)]
    [string]
    $BaseImageName
   )

# OverwriteAMIArtifact.ps1 -BaseImageName w12r2d-14-2
# Source file name is of the form copy-w12r2d-14-2.txt
$sourcepath = "$($env:System_DefaultWorkingDirectory)/copy-$BaseImageName.txt"
Write-Host "sourcepath = $sourcepath"

$targetpath = "$($env:System_DefaultWorkingDirectory)/_Build Image Release Artefacts/aws-$BaseImageName/$BaseImageName.txt"
Write-Host "targetpath = $targetpath"

Copy-Item $sourcepath $targetpath -Force
