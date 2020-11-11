# Resume a specific stack 
param(
[Parameter(Mandatory=$true)]
[String]$Stack
)
"ResumeStack.ps1"

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
    Write-GreenOutput("Resuming stack-name eval$($stack)") | Out-Host

    $match = "eval$($stack)-*"
    $StackInstances = @(Get-ASAutoScalingGroup -Region $Region | where-object {$_.AutoScalingGroupName -like $match } )

    foreach ( $ASGInstance in $StackInstances){
        Write-Host( "$(Get-Date) Resuming process HealthCheck in $($ASGInstance.AutoScalingGroupName)  ")
        Resume-ASProcess -Region $Region -AutoScalingGroupName $ASGInstance.AutoScalingGroupName -ScalingProcess @("HealthCheck")
    }

    Write-Host( "$(Get-Date) Set the ELB $($StackInstances[0].LoadBalancerNames[0]) health check back to the live values")
    Set-ELBHealthCheck -Region $Region -LoadBalancerName $StackInstances[0].LoadBalancerNames[0]  -HealthCheck_Interval 90 -HealthCheck_Timeout 30 -HealthCheck_UnhealthyThreshold 5 -HealthCheck_HealthyThreshold 3 -HealthCheck_Target 'HTTP:80/cgi-bin/probe'    
 } catch {
    $_
}