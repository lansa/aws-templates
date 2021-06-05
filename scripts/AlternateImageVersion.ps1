param (
    [Parameter(Mandatory=$true)]
    [string]
    $Gatestack,
    
    [Parameter(Mandatory=$true)]
    [string]
    $Gateversion,

    [Parameter(Mandatory=$true)]
    [string]
    $CookbooksBranch
)

$SkuName = "$($Gateversion)"
Write-Host "$SkuName"
# Get the URL from the stack
$output = (Get-CFNStack -StackName $($Gatestack) -region ap-southeast-2).Outputs
$websiteUrl = $output | Where-Object {$_.OutputKey -eq "WebsiteURL"}
$url = $websiteUrl.OutputValue
$CookbooksBranch = "$($CookbooksBranch)"

# Autoscaling Instance Id
$childstack = (Get-CFNStack | Where-Object {$_.StackName -match "$($Gatestack)-Web" }).StackName
$webServerGroupResource = (Get-CFNStackResource -StackName $childstack -region ap-southeast-2 -logicalResourceId WebServerGroup)
$instanceDetails = Get-ASAutoScalingInstance | ? {$_.AutoScalingGroupName -eq $webServerGroupResource.PhysicalResourceId} | select -ExpandProperty InstanceId | Get-EC2Instance | select -ExpandProperty RunningInstance | ft InstanceId, PrivateIpAddress
$instanceId = (Get-ASAutoScalingGroup -AutoScalingGroupName $webServerGroupResource.PhysicalResourceId).Instances.InstanceId

#Send command
$DebugPreference = "SilentlyContinue"
$result = Send-SSMCommand -InstanceId $instanceId  -DocumentName "AWS-RunPowerShellScript" -Comment "Checking Image Version" -Parameter @{'commands'=@("c:\lansa\Tests\TestImageVersion.ps1 -ImgName $SkuName")}
do{
    Start-Sleep -Seconds 5
    $status = Get-SSMCommandInvocation -InstanceId $instanceId -CommandId $result.CommandId
} while (($status.Status -eq "Pending") -or ($status.Status -eq "InProgess"))
Write-Host "Command Completed"
$status = Get-SSMCommandInvocation -InstanceId $instanceId -CommandId $result.CommandId
Out-Default -InputObject $status.Status
$output = Get-SSMCommandInvocation -CommandId $result.CommandId -Details $true -InstanceId $instanceId 
Out-Default -InputObject $output.Output
Get-SSMCommandInvocationDetail -InstanceId $instanceId -CommandId $result.CommandId
Write-Host "$output.Output"

