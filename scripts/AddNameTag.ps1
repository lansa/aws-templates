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

$imageId = "$($Copyid)"
New-EC2Tag -Resources $imageId -Tags @{ Key = "Name" ; Value = "$($Copyname)"} | Out-Default | Write-Host
Write-Host "Saving the Copied ami ID $imageId "
#$line = "$imageId - $($Copyname)"
$line = "$imageId"
Write-Host "$line"
$path = "$($env:System_DefaultWorkingDirectory)/$BaseImageName.txt"
Add-Content -Path $path $line | Out-Default | Write-Host
Get-Content -Path $path | Out-Default | Write-Host
