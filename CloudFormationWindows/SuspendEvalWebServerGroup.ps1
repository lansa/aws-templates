# Update all WebServerGroup evaluation stacks to suspend scaling
"SuspendEvalWebServerGroup.ps1"

$Region = 'us-east-1'
$stacks = @(Get-ASTag -Region $Region -Filter @( @{ Name="key"; Values=@("aws:cloudformation:logical-id") } )) | Where-Object {$_.Value -eq 'WebServerGroup'}
foreach ( $stack in $stacks ) {
    $stack.ResourceId

    # Suspend all processes
    Suspend-ASProcess -Region $Region -AutoScalingGroupName $stack.ResourceId
}
