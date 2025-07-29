# SetVersionVariables.ps1
# This script queries all the artefacts published by Build Image Release Artefacts pipeline
# so that they may be used instead of the pipeline variables used previously. Thus the
# pipeline does not need to be configured to run the tests. It automatically works out which tests to run
# based on the artefacts available.
#
Write-Host "Set all pipeline variables to false"
Write-Host "These variables may be accessed in any subsequent stage or job in the pipeline"
Write-Host 'You refer to them as $(Build-w19d-15-0), $(Build-w19d-15-0j), etc.'
Write-Host "This only works because isOutput=false is used"

Write-Host "##vso[task.setvariable variable=Build-w19d-15-0;isOutput=false]False"
Write-Host "##vso[task.setvariable variable=Build-w19d-15-0j;isOutput=false]False"
Write-Host "##vso[task.setvariable variable=Build-w19d-16-0;isOutput=false]False"
Write-Host "##vso[task.setvariable variable=Build-w19d-16-0j;isOutput=false]False"

Write-Host "##vso[task.setvariable variable=Build-w22d-15-0;isOutput=false]False"
Write-Host "##vso[task.setvariable variable=Build-w22d-15-0j;isOutput=false]False"
Write-Host "##vso[task.setvariable variable=Build-w22d-16-0;isOutput=false]False"
Write-Host "##vso[task.setvariable variable=Build-w22d-16-0j;isOutput=false]False"

Write-Host "##vso[task.setvariable variable=Build-w25d-15-0;isOutput=false]False"
Write-Host "##vso[task.setvariable variable=Build-w25d-15-0j;isOutput=false]False"
Write-Host "##vso[task.setvariable variable=Build-w25d-16-0;isOutput=false]False"
Write-Host "##vso[task.setvariable variable=Build-w25d-16-0j;isOutput=false]False"

$path = "$($env:Pipeline_Workspace)/_Build Image Release Artefacts/aws"
Write-Host "Using $path"
if (Test-Path $path) {
    try{
      # Get all .txt files matching the pattern w??d-??-??*.txt
      $files = Get-ChildItem -Path $path -Filter "*.txt" | Where-Object {
         $_.BaseName -match '^w\d{2}d-\d{2}-\d{1}j?$'
      }

      foreach ($file in $files) {
         $buildName = $file.BaseName  # e.g., "w19d-15-0" or "w19d-15-0j"
         $varName = "Build-$buildName"
         Write-Host "##vso[task.setvariable variable=$varName;isOutput=false]True"
      }
    } catch{
        $_ | Out-Default | Write-Host
        Throw "Failed to set pipeline build Variables"
    }
} else {
    Write-Host "Artifact path $path does NOT exist"
}