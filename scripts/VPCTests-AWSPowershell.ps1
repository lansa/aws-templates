$SkuName = "w12r2d-14-2-$(TestVersion-w12r2d-14-2)"
Write-Host $SkuName
# Get the URL from the stack
$output = (Get-CFNStack -StackName $(VpcStack) -region ap-southeast-2).Outputs
$websiteUrl = $output | Where-Object {$_.OutputKey -eq "WebsiteURL"}
$url = $websiteUrl.OutputValue
# Autoscaling Instance Id

$childstack = (Get-CFNStack | Where-Object {$_.StackName -match "$(VpcStack)" }).StackName[0]
$webServerGroupResource = (Get-CFNStackResource -StackName $childstack -region ap-southeast-2 -logicalResourceId WebServerGroup)
$instanceDetails = Get-ASAutoScalingInstance | ? {$_.AutoScalingGroupName -eq $webServerGroupResource.PhysicalResourceId} | select -ExpandProperty InstanceId | Get-EC2Instance | select -ExpandProperty RunningInstance | ft InstanceId, PrivateIpAddress
$instanceId = (Get-ASAutoScalingGroup -AutoScalingGroupName $webServerGroupResource.PhysicalResourceId).Instances.InstanceId

# Run the TestImageVersion script - 
$result = Send-SSMCommand -DocumentName "AWS-RunPowerShellScript" -InstanceId "$instanceId" -Parameter @{commands = ' New-Item -Path "$(CookbooksSource1)\Tests" -ItemType Directory -force -verbose; New-Item -Path "$(CookbooksSource1)\scripts" -ItemType Directory -force -verbose; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/robe070/cookbooks/$(CookbooksBranch)/Tests/TestImageVersion.ps1" -OutFile "$(CookbooksSource1)\Tests\TestImageVersion.ps1" -verbose; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/robe070/cookbooks/$(CookbooksBranch)/scripts/dot-CommonTools.ps1" -OutFile "$(CookbooksSource1)\scripts\dot-CommonTools.ps1" -verbose; "$(CookbooksSource1)\scripts\dot-CommonTools.ps1"; $(CookbooksSource1)\Tests\TestImageVersion.ps1 -ImgName '+$SkuName}

while ($result.Status -eq "Pending" -or $result.Status -eq "InProgress"){
    $result = Get-SSMCommand -InstanceId $result.InstanceId -CommandId $result.CommandId}
$result | Out-Default | Write-Host
if ($result.Status -eq "Success") {
 Write-Host "Tested the image version in the VMSS successfully."
} else {
 throw ($result.Status)
}

