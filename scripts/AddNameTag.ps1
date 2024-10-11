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
$line = "$imageID"
Write-Host "$line"
$path = "$($env:Pipeline_Workspace)/$BaseImageName.txt"
Add-Content -Path $path $line | Out-Default | Write-Host
Get-Content -Path $path | Out-Default | Write-Host