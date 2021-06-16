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

Remove-Item $targetpath -ErrorAction SilentlyContinue

if (Test-Path $sourcepath) {
    Write-Host "Copying $sourcepath to $targetpath"
    Copy-Item $sourcepath $targetpath
} else {
    Write-Host "$sourcepath does not exist"
}

