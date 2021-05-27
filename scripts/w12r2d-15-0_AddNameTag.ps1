$imageId = "$(Copy.id)"
New-EC2Tag -Resources $imageId -Tags @{ Key = "Name" ; Value = "$(Copy.name)"}
Write-Host "Saving the Copied ami ID $imageId " | Out-Default | Write-Host
$line = "$imageId - $(Copy.name)"
Write-Host "$line"
$path = "$(System.DefaultWorkingDirectory)/copy-w12r2d-15-0.txt"
Add-Content -Path $path $line
$content = Get-Content -Path $path
Write-Host "$content"

