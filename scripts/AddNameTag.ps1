#e.g AddNameTag.ps1 -BaseImageName w12r2d-14-2
param (
    [Parameter(Mandatory=$true)]
    [string]
    $BaseImageName,

    [Parameter(Mandatory=$true)]
    [string]
    $Copyid,

    [Parameter(Mandatory=$true)]
    [string]
    $Copyname
)

$imageID = "$($Copyid)"
New-EC2Tag -Resource $imageID -Tag @{ Key = "Name" ; Value = "$($Copyname)"} | Out-Default | Write-Host
Write-Host "Saving the Copied ami ID $imageID "
#$line = "$imageID - $($Copyname)"
#$line = "$imageID"
$path = "$($env:Pipeline_Workspace)/$BaseImageName.txt"
Write-Host "Adding this AMI: $imageID to $path"
Set-Content -Path $path $imageID | Out-Default | Write-Host

Write-Host "Contents of ${path}:"
Get-Content -Path $path | Out-Default | Write-Host