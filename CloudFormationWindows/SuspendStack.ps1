# Suspend a specific stack

param(
[Parameter(Mandatory=$true)]
[String]$Stack
)

"SuspendStack.ps1"

$script:IncludeDir = $null
if ( !$script:IncludeDir)
{
    # Log-Date can't be used yet as Framework has not been loaded

	Write-Host "Initialising environment - presumed not running through RemotePS"
	$MyInvocation.MyCommand.Path
	$script:IncludeDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\scripts'
    Write-Host "Include path $script:IncludeDir"
	. "$script:IncludeDir\Init-Baking-Vars.ps1"
	. "$script:IncludeDir\Init-Baking-Includes.ps1"
}
else
{
	Write-Output "$(Log-Date) Environment already initialised"
}

$a = Get-Date
Write-Host "$($a.ToLocalTime()) Local Time"
Write-Host "$($a.ToUniversalTime()) UTC"

try {
    $Region = 'us-east-1'

    # Enumerate all the ASGs for each stack
    # Match on stack name
    Write-GreenOutput("Suspending stack-name eval$($stack)") | Out-Host

    $match = "eval$($stack)-*"
    $StackInstances = @(Get-ASAutoScalingGroup -Region $Region | where-object {$_.AutoScalingGroupName -like $match } )

    foreach ( $ASGInstance in $StackInstances){
        Write-Host( "$(Get-Date) Suspending process HealthCheck in $($ASGInstance.AutoScalingGroupName)  ")
        Suspend-ASProcess -Region $Region -AutoScalingGroupName $ASGInstance.AutoScalingGroupName -ScalingProcess @("HealthCheck")
    }

    Write-Host( "$(Get-Date) Make the ELB $($StackInstances[0].LoadBalancerNames[0]) health check as long as possible so that ALARMs are not sent")
    Set-ELBHealthCheck -Region $Region -LoadBalancerName $StackInstances[0].LoadBalancerNames[0]  -HealthCheck_Interval 300 -HealthCheck_Timeout 60 -HealthCheck_UnhealthyThreshold 10 -HealthCheck_HealthyThreshold 2 -HealthCheck_Target 'HTTP:80/cgi-bin/probe'
 } catch {
    $_
}