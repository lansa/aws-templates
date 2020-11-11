Param(
    [Parameter(Mandatory)]
        [ValidateSet('Live','Test','Dev')]
        [string] $StackType
)

"ChangeInstanceLifetime.ps1"
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

        # Use a numbered loop so that individual stacks can be updated
        # Note that ALL instances are ALWAYS terminated.

        for ( $i = $StackStart; $i -le $StackEnd; $i++) {
            # Match on stack name too
            if ( $J -eq 1 ){
                $match = "eval$i-DB*"
                $lifetime = 5270400 # 61 days
            } else {
                $match = "eval$i-Web*"
                $lifetime = 5788800 # 67 days
            }

            $StackInstances = @(Get-ASAutoScalingInstance -Region $Region | where-object {$_.AutoScalingGroupName -like $match } )

            if ( $StackInstances){
                Write-Output( "$(date) Instances to be terminated...")
                $StackInstances | Format-Table

                foreach ( $StackInstance in $StackInstances ) {
                    # Keep a list of all the Auto Scaling Groups
                    $ASG = $StackInstance.AutoScalingGroupName
                    $ASG

                    # Ensure that the ASG is free to behave normally by resuming all autoscaling processes
                    Resume-ASProcess -Region $Region -AutoScalingGroupName $ASG

                    # Change property
                    Write-Output( "$(date) Updating $ASG $($StackInstance.InstanceId)")
                    Update-ASAutoScalingGroup -region $Region -autoscalinggroupname $ASG -maxinstancelifetime $lifetime -ErrorAction Stop
                }
            }
        }
    }

} catch {
    $_
    Write-Output( "$(date) ASG Update failure")
    cmd /c exit -1
    exit
}
Write-Output( "$(date) ASG Update successful.")
cmd /c exit 0