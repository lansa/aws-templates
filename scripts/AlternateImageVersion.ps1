param (
    [Parameter(Mandatory=$true)]
    [string]
    $Gatestack,

    [Parameter(Mandatory=$true)]
    [string]
    $Gateversion,

    [Parameter(Mandatory=$true)]
    [string]
    $Region
)

$SkuName = "$($Gateversion)"
Write-Host "Image Name $SkuName"

# Autoscaling Instance Id
$childstack = (Get-CFNStack | Where-Object {$_.StackName -match "$($Gatestack)-Web" }).StackName
$webServerGroupResource = (Get-CFNStackResource -StackName $childstack -Region $($Region) -logicalResourceId WebServerGroup)
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
Write-Host "Command Result Status:"
$status = Get-SSMCommandInvocation -InstanceId $instanceId -CommandId $result.CommandId
Out-Default -InputObject $status.Status

Write-Host "Command Result Details:"
$output = Get-SSMCommandInvocation -CommandId $result.CommandId -Details $true -InstanceId $instanceId
Out-Default -InputObject $output.Output

Write-Host "Command Result Invocation Details:"
Get-SSMCommandInvocationDetail -InstanceId $instanceId -CommandId $result.CommandId | Out-Default | Write-Host
