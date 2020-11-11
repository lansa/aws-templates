# Update all evaluation stacks to resume scaling. Make sure all ELBs have all instances InService BEFORE running this!
Param(
    [Parameter(Mandatory)]
        [ValidateSet('All', 'Live','Test','Dev')]
        [string] $StackType,
    [Parameter(Mandatory)]
        [ValidateSet('All','KeepAlive','Custom')]
        [string] $ScalingProcesses
)
$MyInvocation.MyCommand.Name | Out-Default | Write-Host

[System.Collections.ArrayList]$stacklist = @()
switch ( $StackType ) {
    'All' {
        $StackStart = 1
        $StackEnd = 10
        $stacklist.add(20) | Out-Null
        $stacklist.add(30) | Out-Null
    }
    'Live' {
        $StackStart = 1
        $StackEnd = 10
    }
    'Test' {
        $StackStart = 20
        $StackEnd = 20
    }
    'Dev' {
        $StackStart = 30
        $StackEnd = 30
    }
    'Custom' {
        $StackStart = 9
        $StackEnd = 9
    }
}

For ( $stack = $StackStart; $stack -le $StackEnd; $stack++) {
    $stacklist.add($stack) | Out-Null
}

[System.Collections.ArrayList]$ProcessList = @()

switch ( $ScalingProcesses ) {
    'All' {
        # Do nothing - use empty list
    }
    'KeepAlive' {
        $ProcessList = @("Terminate", "ReplaceUnhealthy")
    }
    'Custom' {
        # Edit this to what ever you need
        $ProcessList = @("Terminate", "ReplaceUnhealthy")
    }
}

$Region = 'us-east-1'

foreach ( $stack in $stacklist) {
    $WebServerGroups = @(Get-ASTag -Region $Region -Filter @( @{ Name="key"; Values=@("aws:cloudformation:logical-id") } )) | Where-Object {$_.Value -eq 'WebServerGroup' -and ($_.ResourceId -like "eval$stack-*")}
    foreach ( $WebServerGroup in $WebServerGroups ) {
        $WebServerGroup.ResourceId

        # Resume all processes
        Resume-ASProcess -Region $Region -AutoScalingGroupName $WebServerGroup.ResourceId $ProcessList
    }

    $DBWebServerGroups = @(Get-ASTag -Region $Region -Filter @( @{ Name="key"; Values=@("aws:cloudformation:logical-id") } )) | Where-Object {$_.Value -eq 'DBWebServerGroup' -and ($_.ResourceId -like "eval$stack-*")}
    foreach ( $DBWebServerGroup in $DBWebServerGroups ) {
        $DBWebServerGroup.ResourceId
        # Resume all processes
        Resume-ASProcess -Region $Region -AutoScalingGroupName $DBWebServerGroup.ResourceId $ProcessList
    }
}