# Call the Vl Web Test server module directly on each instance, not through the load balancer

# Could be improved:
# 1) Also run the web page too - xvlwebtst

Param(
    [Parameter(Mandatory)]
        [ValidateSet('Live','Test','Dev','All', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '20', '30')]
        [string] $StackType
)

'CheckVLWebStatus.ps1'

function Summary {
    If ( !$StackError ) {
        Write-Host "All Apps in stacks " -NoNewline
        $first = $true
        foreach ( $stack in $stacklist) {
            if ( $first ) {
                $first = $false
            } else {
                Write-Host ', ' -NoNewline
            }
            Write-Host $Stack -NoNewline
        }
        Write-Host " are in service"
    } else {
        Write-Output "" | Out-Host
        if ( $404count -gt 0 -or $defaultcount -gt 0  ) {
            Write-RedOutput "Test failed"  | Out-Host
        }
        if ( $404count -gt 0 ){ Write-RedOutput "404 usually means the Listener is not running this is important to fix ASAP. And its simple to fix. Just re-deploy the app"}
        if ( $500count -gt 0 ){ Write-FormattedOutput "500 usually means Free Trial was installed but no app was deployed. Look at git repo and check that there is just the one commit. If thats the case then this error may be ignored." -ForegroundColor 'yellow'}
        if ( $defaultcount -gt 0 ){ Write-FormattedOutput "Other response codes have unknown cause" -ForegroundColor 'magenta'}
    }
    Write-Host ""
}

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

$ProgressPreference = 'SilentlyContinue' # Speed things up by a factor of 10 ref: https://stackoverflow.com/questions/17325293/invoke-webrequest-post-with-parameters

try {
    $Region = 'us-east-1'
    $Perpetual = $true
    [Decimal]$StackStart=0
    [Decimal]$StackEnd=0
    [Decimal]$Stack=0
    [System.Collections.ArrayList]$stacklist = @()

    switch ( $StackType ) {
        {$_ -eq 'Live' -or $_ -eq 'All'} {
            $StackStart = 1
            $StackEnd = 10

            For ( $stack = $StackStart; $stack -le $StackEnd; $stack++) {
                $stacklist.add($stack) | Out-Null
            }
        }
        {$_ -eq 'Test' -or $_ -eq 'All'} {
            $stacklist.add(20) | Out-Null
        }
        {$_ -eq 'Dev' -or $_ -eq 'All'} {
            $stacklist.add(30) | Out-Null
        }
        # Handle numeric entry
        Default {
            $StackNum = [Decimal] $_
            $stacklist.add($StackNum) | Out-Null
        }
    }

    if ( $stacklist.Count -eq 0 ) {
        throw "There are no stacks requested"
    }

    Write-Host( "Stack List: $($Stacklist -join ',')")

    $Loop = 0
    do {
        $StackError = $false
        $FoundInstance = $false
        $404count = 0
        $500count = 0
        $defaultcount = 0
        $Loop++

        # Traverse each ASG for each stack to enumerate all the instances
        for ($j = 1; $j -le 2; $j++) {
            # Use a numbered loop so that individual stacks can be updated
            foreach ( $stack in $stacklist) {
                # Match on stack name too
                if ( $J -eq 1 ){
                    $match = "eval$stack-DB*"
                } else {
                    $match = "eval$stack-Web*"
                }

                Write-GreenOutput $match | Out-Host
                $StackInstances = @(Get-ASAutoScalingInstance -Region $Region | where-object {$_.AutoScalingGroupName -like $match } )

                if ( $StackInstances){
                    $FoundInstance = $true
                    foreach ( $StackInstance in $StackInstances ) {
                        $EC2Detail = Get-EC2Instance -Region $Region $StackInstance.InstanceId

                        $IPAddress = $Ec2Detail[0].Instances[0].PublicIpAddress

                        try {
                            # HTTP:80/cgi-bin/probe
                            $url = "http://$IPAddress/cgi-bin/probe"
                            $response = Invoke-WebRequest -Uri $url -UseBasicParsing
                            $ResponseCode = $response.StatusCode
                        } catch {
                            $StackError = $true
                            $ResponseCode = $_.Exception.Response.StatusCode.Value__
                            Write-FormattedOutput "$ResponseCode Stack $stack Installation in Progress $url" -ForegroundColor 'red'
                            Start-Sleep 0
                            continue
                        }

                        Write-Host "$Loop $($(Get-Date).ToLocalTime()) Local Time EC2 $($Ec2Detail[0].Instances[0].InstanceId) $IPAddress" -NoNewline
                        $max = 10
                        for ( $appl = 1; $appl -le $max; $appl++ ) {
                            Write-Host -NoNewline " $appl"
                            try {
                                $url = "http://$IPAddress/app$appl/lansaweb?w=XVLSMTST&r=GETRESPONSE&vlweb=1&part=dem&lang=ENG"
                                $response = Invoke-WebRequest -Uri $url -UseBasicParsing
                                $ResponseCode = $response.StatusCode
                                switch ($ResponseCode) {
                                    200 { }
                                    404 { Write-Host "";Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'red' | Out-Host; $StackError = $true; $404count++ }
                                    500 { Write-Host "";Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'yellow' | Out-Host; $StackError = $true; $500count++ }
                                    default { Write-Host "";Write-FormattedOutput"$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'Magenta' | Out-Host; $StackError = $true; $defaultcount++ }
                                }
                            } catch {
                                Write-Host ""
                                $StackError = $true
                                $ResponseCode = $_.Exception.Response.StatusCode.Value__
                                switch ($ResponseCode) {
                                    404 { Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'red' | Out-Host; $404count++ }
                                    500 { Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'yellow' | Out-Host; $500count++ }
                                    default { Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'Magenta' | Out-Host; $defaultcount++ }
                                }
                            }
                            if ( $appl -eq 1) {
                                # Workaround for IIS Plugin not coping with too many requests when first starting up
                                # First request causes all the listener connections to be setup
                                # 15 second is too short. Still get failures.
                                Start-Sleep 0
                            }
                        }
                        Write-Host ""
                    }
                }
            }
        }
        Summary
    } while ($Perpetual -and $FoundInstance)

    if ( -not $FoundInstance ) {
        $StackError = $true
        Write-RedOutput "Test failed"  | Out-Host
        throw "No EC2 instances found"
    }
} catch {
    $_
}
