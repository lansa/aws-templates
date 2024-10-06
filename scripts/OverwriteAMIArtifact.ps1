# OverwriteAMIArtifact.ps1 -BaseImageName w12r2d-14-2
# Source file name is of the form copy-w12r2d-14-2.txt
$sourcepath = "$($env:Pipeline_Workspace)/$($GitRepoName)"/templates/support/scalable/ami-list/*.txt"
Write-Host "sourcepath = $sourcepath"

$targetpath = "$($env:Pipeline_Workspace)/$($GitRepoName)"/_Build Image Release Artefacts/aws"
Write-Host "targetpath = $targetpath"

Remove-Item $targetpath/* -ErrorAction SilentlyContinue

if (Test-Path $sourcepath) {
    Write-Host "Copying $sourcepath to $targetpath"
    Copy-Item $sourcepath $targetpath
    Write-Host "Listing files in $targetpath path"
    dir $targetpath
} else {
    Write-Host "$sourcepath does not exist"
}
