#e.g AddNameTag.ps1 -BaseImageName w12r2d-14-2

param (
    [Parameter(Mandatory=$true)]
    [string]
    $BaseImageName,

    [Parameter(Mandatory=$true)]
    [string]
    $Copyid
)

$imageId = "$($Copyid)"
New-EC2Tag -Resources $imageId -Tags @{ Key = "Name" ; Value = "$(Copy.name)"}
Write-Host "Saving the Copied ami ID $imageId " | Out-Default | Write-Host
$line = "$imageId - $(Copy.name)"
Write-Host "$line"
$path = "$($env:System_DefaultWorkingDirectory)/copy-$BaseImageName.txt"
Add-Content -Path $path $line
$content = Get-Content -Path $path
Write-Host "$content"
#Out-File -FilePath (Join-Path $(Build.ArtifactStagingDirectory) "copy-w12r2d-14-2.txt") -InputObject $line | Out-Default | Write-Host

