# Set the Gate variable if the file exists
$path = "$(System.DefaultWorkingDirectory)/_Build Image Release Artefacts/aws-w16d-14-2/w16d-14-2.txt"
if (Test-Path $path) {
$amiID = Get-Content -Path $path 
Write-Host $amiID | Out-Default | Write-Verbose
$imageName = (Get-EC2Image -ImageId $amiID).Name
$imageName -match 'w16d-14-2[-]?[0-9]+'
$version = $Matches[0]
Write-Host "Version : $version"
$stackname = "$version-$(stackname)"
Write-Host "Stack name : $stackname"
#Set Variables
Write-Host "##vso[task.setvariable variable=stack;isOutput=true]$stackname" | Out-Default | Write-Verbose
#Set Variables
Write-Host "##vso[task.setvariable variable=version;isOutput=true]$version" | Out-Default | Write-Verbose
Write-Host "##vso[task.setvariable variable=ImageID;isOutput=true]$amiID" | Out-Default | Write-Verbose 
 Write-Host "##vso[task.setvariable variable=IsEnabled;isOutput=true]True" | Out-Default | Write-Verbose
    Write-host "The value of Variable IsEnabled is updated to True and output variable ImageID to $amiID" | Out-Default | Write-Verbose
}

