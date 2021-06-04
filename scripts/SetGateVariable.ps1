param ($BaseImageName)
#SetGateVariable.ps1 -BaseImageName w12r2d-14-2
# Set the Gate variable if the file exists
Write-Host "##vso[task.setvariable variable=IsEnabled;isOutput=true]False" | Out-Default | Write-Verbose
$path = "$($env:System_DefaultWorkingDirectory)/_Build Image Release Artefacts/aws-$BaseImageName/$BaseImageName.txt"
if (Test-Path $path) {
  Write-Host $path | Out-Default | Write-Verbose
  $amiID = Get-Content -Path $path 
  Write-Host $amiID | Out-Default | Write-Verbose
  $id =$amiID
  $imageName = (Get-EC2Image -ImageId $id).Name
  $imageName -match "$BaseImageName[-]?[0-9]+"
  $version = $Matches[0]
  Write-Host "Version : $version"
  $stackname = "$version-$(stackname)"
  Write-Host "Stack name : $stackname"
  #Set Variables
  Write-Host "##vso[task.setvariable variable=stack;isOutput=true]$stackname" | Out-Default | Write-Verbose
  Write-Host "##vso[task.setvariable variable=version;isOutput=true]$version" | Out-Default | Write-Verbose
  Write-Host "##vso[task.setvariable variable=ImageID;isOutput=true]$amiID" | Out-Default | Write-Verbose 
  Write-Host "##vso[task.setvariable variable=IsEnabled;isOutput=true]True" | Out-Default | Write-Verbose
  Write-host "The value of Variable IsEnabled is updated to True and output variable ImageID to $amiID" | Out-Default | Write-Verbose
} else {
  Write-Host "Artifact path: $path does NOT exist for $BaseImageName" | Out-Default | Write-Verbose
}

