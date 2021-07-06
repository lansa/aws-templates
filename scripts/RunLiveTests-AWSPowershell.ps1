#Expect Below paramter to be passed from pipeline.
# 1. BaseImageName : Base image name e.g w12r2d-14-2
# 2. Gatestack : Stack Name either production or Vpc
# 3. IsVpcStack : Pass yes if it is VpcStack otherwise no
param (
    [Parameter(Mandatory=$true)]
    [string]
    $BaseImageName,

    [Parameter(Mandatory=$true)]
    [string]
    $Gatestack,
  
    [Parameter(Mandatory=$true)]
    [string]
    $IsVpcStack
)

if ($imageReleaseState -eq "Production") {
    $SkuName = "$BaseImageName-$(TestVersionPrev-$BaseImageName)"
} else {
    $SkuName = "$BaseImageName-$(TestVersion-$BaseImageName)"   
}
Write-Host $SkuName

# Autoscaling Instance Id
if ("$(IsVpcStack)" -eq "yes") {
    $childstack = (Get-CFNStack | Where-Object {$_.StackName -match "$($Gatestack)" }).StackName[0]
} else {
    $childstack = (Get-CFNStack | Where-Object {$_.StackName -match "$($Gatestack)-Master" }).StackName[2]
}
Write-Host $childstack

$arguments = @("-SkuName", "$SkuName ")
$arguments = $arguments + @("-childstack", "$childstack ")
& "$PSScriptRoot\AlternateImageVersion.ps1 " + $arguments

