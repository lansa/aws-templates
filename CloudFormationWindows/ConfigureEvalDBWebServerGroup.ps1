# Configure all DBWebServerGroup evaluation stacks to suspend termination when the VM is occupied installing or the like.
"ConfigureEvalDBWebServerGroup.ps1"

$Region = 'us-east-1'
$stacks = @(Get-ASTag -Region $Region -Filter @( @{ Name="key"; Values=@("aws:cloudformation:logical-id") } )) | Where-Object {$_.Value -eq 'DBWebServerGroup'}
foreach ( $stack in $stacks ) {
    $stack.ResourceId
    # Resume all processes, except HealthCheck. Also see WinupdEval.ps1 for similar code
    Resume-ASProcess -Region $Region -AutoScalingGroupName $stack.ResourceId -ScalingProcess @("Launch", "AlarmNotification", "ReplaceUnhealthy", "AZRebalance", "ScheduledActions", "AddToLoadBalancer", "Terminate", "RemoveFromLoadBalancerLowPriority")
    Suspend-ASProcess -Region $Region -AutoScalingGroupName $stack.ResourceId -ScalingProcess @("HealthCheck")
}
