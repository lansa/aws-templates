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
    $Output = Get-SSMCommandInvocation -InstanceId $instanceId -CommandId $result.CommandId
} while (($Output.Status -eq "Pending") -or ($Output.Status -eq "InProgess"))
$Output = Get-SSMCommandInvocationDetail -InstanceId $instanceId -CommandId $result.CommandId | Out-Default | Write-Host
Write-Host $($Output.StandardOutputContent)

$Output = Get-SSMCommandInvocation -InstanceId $instanceId -CommandId $result.CommandId
Write-Host "Command Result Status: $($Output.Status)"
Out-Default -InputObject $Output.Status

