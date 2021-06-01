# Set the Gate variable if the file exists
$path = "$(System.DefaultWorkingDirectory)/_Build Image Release Artefacts/aws-$AWSImageName/$AWSImageName.txt"
if (Test-Path $path) {
  $amiID = Get-Content -Path $path 
  Write-Host $amiID | Out-Default | Write-Verbose
  $id =$amiID
  $imageName = (Get-EC2Image -ImageId $id).Name
  $imageName -match "$AWSImageName[-]?[0-9]+"
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
}

