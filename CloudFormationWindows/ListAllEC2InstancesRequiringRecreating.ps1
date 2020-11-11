# List all EC2 instances that have an empty LaunchConfigurationName which indicates the stack update
# has introduced a change which requires the ASG instance to be terminated and re-created.
# This should be done in a controlled manner using ReplaceAllEc2InstancesEvalStacks.ps1. At least one
# instance is left in service. Use ShowLoadBalancerInstanceHealth.ps1 to check that all instances are 
# In Service before running ReplaceAllEc2InstancesEvalStacks.ps1
"ListAllEC2InstancesRequiringRecreating.ps1"

function Write-FormattedOutput
{
    [CmdletBinding()]
    Param(
         [Parameter(Mandatory=$True,Position=1,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)][Object] $Object,
         [Parameter(Mandatory=$False)][ConsoleColor] $BackgroundColor,
         [Parameter(Mandatory=$False)][ConsoleColor] $ForegroundColor
    )    

    # save the current color
    $bc = $host.UI.RawUI.BackgroundColor
    $fc = $host.UI.RawUI.ForegroundColor

    # set the new color
    if($BackgroundColor -ne $null)
    { 
       $host.UI.RawUI.BackgroundColor = $BackgroundColor
    }

    if($ForegroundColor -ne $null)
    {
        $host.UI.RawUI.ForegroundColor = $ForegroundColor
    }

    Write-Output $Object
  
    # restore the original color
    $host.UI.RawUI.BackgroundColor = $bc
    $host.UI.RawUI.ForegroundColor = $fc
}

date
$Region = 'us-east-1'

try {
    # save the current colors
    $bc = $host.UI.RawUI.BackgroundColor
    $fc = $host.UI.RawUI.ForegroundColor

    $StackInstances = @(Get-ASAutoScalingInstance -Region $Region | where-object {[string]::IsNullOrEmpty($_.LaunchConfigurationName)})

    if ( $StackInstances ) {
        $host.UI.RawUI.ForegroundColor = 'Red'
        $StackInstances  | format-table
    } else {
        Write-FormattedOutput "$(date) No instances require recreating"  -ForegroundColor 'Green'
    }
} finally {
    # restore the original colors
    $host.UI.RawUI.BackgroundColor = $bc
    $host.UI.RawUI.ForegroundColor = $fc
}