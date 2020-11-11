# Replace all EC2 instances so that template changes are applied to all evaluation instances
# E.g. Security Group changes require a new ASG launch configuration
# List all EC2 instances.
# This should be done in a controlled manner using ReplaceAllEc2InstancesEvalStacks.ps1. At least one
# instance is left in service. Use ShowLoadBalancerInstanceHealth.ps1 to check that all instances are
# In Service before running ReplaceAllEc2InstancesEvalStacks.ps1

Param(
    [Parameter(Mandatory)]
        [ValidateSet('Live','Test','Dev')]
        [string] $StackType
)

"ReplaceAllEC2InstancesEvalStacks.ps1"
date

$Region = 'us-east-1'

switch ( $StackType ) {
    'Live' {
        $GitRepoBranch = 'support/L4W14200_paas'
        $StackStart = 1
        $StackEnd = 10
    }
    'Test' {
        $GitRepoBranch = 'patch/paas'
        $StackStart = 20
        $StackEnd = 20
    }
    'Dev' {
        $GitRepoBranch = 'debug/paas'
        $StackStart = 30
        $StackEnd = 30
    }
}

try {

    for ($j = 1; $j -le 2; $j++) {
        if ( $J -eq 1 ){
            Write-Output "$(date) DBWebServerGroup"
        } else {
            Write-Output "$(date) WebServerGroup"
        }

        $ELBS = @()
        $ASGS = @()

        # Use a numbered loop so that individual stacks can be updated
        # Note that ALL instances are ALWAYS terminated.

        for ( $i = $StackStart; $i -le $StackEnd; $i++) {
            # Match on stack name too
            if ( $J -eq 1 ){
                $match = "eval$i-DB*"
                & (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "SuspendStack.ps1") -Stack $i
            } else {
                $match = "eval$i-Web*"
            }

            $StackInstances = @(Get-ASAutoScalingInstance -Region $Region | where-object {$_.AutoScalingGroupName -like $match } )

            if ( $StackInstances){
                Write-Output( "$(date) Instances to be terminated...")
                $StackInstances | Format-Table

                foreach ( $StackInstance in $StackInstances ) {
                    # Keep a list of all the Auto Scaling Groups
                    $ASG = $StackInstance.AutoScalingGroupName
                    $ASGs += $ASG

                    # Ensure that the ASG is free to behave normally by resuming all autoscaling processes
                    Resume-ASProcess -Region $Region -AutoScalingGroupName $ASG

                    # Keep a list of all the LoadBalancers
                    $ELB = Get-ASLoadBalancer -Region $Region -AutoScalingGroupName $StackInstance.AutoScalingGroupName
                    $ELBs += $ELB

                    # Terminate instance
                    Write-Output( "$(date) Terminating $($StackInstance.InstanceId)")
                    Remove-EC2Instance -Region $Region $StackInstance.InstanceId -Force -ErrorAction Continue
                }
            }
        }

        # *****************************************************************************
        # Terminate EC2 instances and wait long enough that the instances are registered
        # with every ELB then wait for all instances to come into service before proceeding
        # *****************************************************************************

        $ASGs = $ASGs | select-object -Unique

        Write-Output( "$(date) ASGs to be updated...")
        $ASGs | Format-Table
        if ( $J -eq 1 ){
            $ASG_DB = $ASGs
        }
        $ELBs = $ELBs | select-object -property LoadBalancerName -Unique

        Write-Output( "$(date) ELBs to be monitored...")
        $ELBs | Format-Table

        if ( $ASGs.Length -gt 0) {
            Write-Output( "$(date) Wait 5 minutes to give time for instances to be instantiated and added to the ELBs")
            Start-Sleep 300
        }

        # *****************************************************************************
        # Wait for all instance in ELB to come into service before continuing with WebServerGroup
        # *****************************************************************************
        Write-Output("$(date) Wait for Load Balancers to be InService")
        foreach ( $ELB in $ELBs ) {
            Write-Output("$(date) ELB $($ELB.LoadBalancerName)")
            $ELBInstances = @(Get-ELBInstanceHealth -Region $Region -LoadBalancerName $ELB.LoadBalancerName)
            $AllInService = $false
            while ( -not $AllInService ) {
                $AllInService = $true
                foreach ( $Instance in $ELBInstances ) {
                    Write-Output( "$(date) $($Instance.InstanceId) is $($Instance.State)")
                    if ( $Instance.State -ne 'InService') {
                        $AllInService = $false
                        Write-Output("$(date) Waiting")
                        Start-Sleep( 30)
                        break
                    }
                }
                $ELBInstances = @(Get-ELBInstanceHealth -Region $Region -LoadBalancerName $ELB.LoadBalancerName)
            }
        }
    }

    # *****************************************************************************
    # Resume stacks
    # *****************************************************************************

    for ( $i = $StackStart; $i -le $StackEnd; $i++) {
        & (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "ResumeStack.ps1") -Stack $i
    }
} catch {
    $_
    Write-Output( "$(date) ASG Update failure")
    cmd /c exit -1
    exit
}
Write-Output( "$(date) ASG Update successful.")
cmd /c exit 0