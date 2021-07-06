param (
    [Parameter(Mandatory=$false)]
    [string]
    $Gatestack,

    [Parameter(Mandatory=$false)]
    [string]
    $Gateversion,

    [Parameter(Mandatory=$false)]
    [string]
    $Region,

    [Parameter(Mandatory=$false)]
    [string]
    $SkuName,

    [Parameter(Mandatory=$false)]
    [string]
    $childstack
)

# Autoscaling Instance Id
if ( $Gatestack -ne "" )
{
    $SkuName = "$($Gateversion)"
    $childstack = (Get-CFNStack | Where-Object {$_.StackName -match "$($Gatestack)-Web" }).StackName
}

Write-Host "Image Name $SkuName"

$webServerGroupResource = (Get-CFNStackResource -StackName $childstack -Region $($Region) -logicalResourceId WebServerGroup)
$instanceDetails = Get-ASAutoScalingInstance | ? {$_.AutoScalingGroupName -eq $webServerGroupResource.PhysicalResourceId} | select -ExpandProperty InstanceId | Get-EC2Instance | select -ExpandProperty RunningInstance | ft InstanceId, PrivateIpAddress
$instanceId = (Get-ASAutoScalingGroup -AutoScalingGroupName $webServerGroupResource.PhysicalResourceId).Instances.InstanceId

#Send command
$DebugPreference = "SilentlyContinue"
$result = Send-SSMCommand -InstanceId $instanceId  -DocumentName "AWS-RunPowerShellScript" -Comment "Checking Image Version" -Parameter @{'commands'=@("c:\lansa\Tests\TestImageVersion.ps1 -ImgName $SkuName")}
do{
    Start-Sleep -Seconds 5
    $Output = Get-SSMCommandInvocation -InstanceId $instanceId -CommandId $result.CommandId
} while (($Output.Status -eq "Pending") -or ($Output.Status -eq "InProgress"))
Write-Host "Command Result Status: $($Output.Status)"

$Output = Get-SSMCommandInvocationDetail -InstanceId $instanceId -CommandId $result.CommandId
$Output.StandardOutputContent | Out-Default | Write-Host

if ($Output.StandardErrorContent -ne ""){
    $Output.StandardErrorContent | Out-Default | Write-Host
throw
}
