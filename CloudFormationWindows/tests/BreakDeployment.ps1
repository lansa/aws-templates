# Call the Vl Web Test server module directly on each instance, not through the load balancer

# Could be improved:
# 1) Also run the web page too - xvlwebtst

Param(
    [Parameter(Mandatory)]
        [ValidateSet('Test','Dev1','Dev2','Custom')]
        [string] $StackType
)

'BreakDeployment.ps1'

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
        Write-Host " deployed"
    } else {
        Write-Output "" | Out-Default | Write-Host
        if ( $404count -gt 0 -or $defaultcount -gt 0  ) {
            Write-RedOutput "Test failed"  | Out-Default | Write-Host
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
	$script:IncludeDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\scripts'
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

$ParentDir = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

try {
    $Region = 'us-east-1'
    $Perpetual = $true
    [Decimal]$StackStart=0
    [Decimal]$StackEnd=0
    [Decimal]$Stack=0
    [Decimal]$appl = 2   # Just test app2

    switch ( $StackType ) {
        'Test' {
            $GitRepoBranch = 'patch/paas'
            $StackStart = 20
            $StackEnd = 20
        }
        'Dev1' {
            $GitRepoBranch = 'debug/paas'
            $StackStart = 30
            $StackEnd = 30
            $appl = 1
        }
        'Dev2' {
            $GitRepoBranch = 'debug/paas'
            $StackStart = 30
            $StackEnd = 30
        }
        'Custom' {
            $GitRepoBranch = 'debug/paas'
            $StackStart = 30
            $StackEnd = 30
        }
    }

    [System.Collections.ArrayList]$stacklist = @()
    For ( $stack = $StackStart; $stack -le $StackEnd; $stack++) {
        $stacklist.add($stack) | Out-Null
    }

    $Loop = 0
    do {
        $StackError = $false
        $FoundInstance = $false
        $404count = 0
        $500count = 0
        $503count = 0
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

                Write-GreenOutput $match | Out-Default | Write-Host
                $StackInstances = @(Get-ASAutoScalingInstance -Region $Region | where-object {$_.AutoScalingGroupName -like $match } )

                if ( $StackInstances){
                    $FoundInstance = $true
                    foreach ( $StackInstance in $StackInstances ) {
                        $EC2Detail = Get-EC2Instance -Region $Region $StackInstance.InstanceId

                        $IPAddress = $Ec2Detail[0].Instances[0].PublicIpAddress

                        Write-Host "$Loop $($(Get-Date).ToLocalTime()) Local Time EC2 $($Ec2Detail[0].Instances[0].InstanceId) $IPAddress" -NoNewline
                        Write-Host -NoNewline " $appl"
                        try {
                            $url = "http://$($IPAddress):8101/Deployment/Start/APP$($appl)"
                            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ContentType "application/json" -Method POST -Body "{ 'source':'TestScript' }"
                            $ResponseCode = $response.StatusCode
                            switch ($ResponseCode) {
                                200 { Write-Host "";Write-Host "Deployment successful"}
                                404 { Write-Host "";Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'red' | Out-Default | Write-Host; $StackError = $true; $404count++ }
                                500 { Write-Host "";Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'yellow' | Out-Default | Write-Host; $StackError = $true; $500count++ }
                                503 { Write-Host "";Write-FormattedOutput "Installation in progress. $ResponseCode Stack $stack App $appl $url" -ForegroundColor 'yellow' | Out-Default | Write-Host; $StackError = $true; $503count++ }
                                default { Write-Host "";Write-FormattedOutput"$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'Magenta' | Out-Default | Write-Host; $StackError = $true; $defaultcount++ }
                            }
                        } catch {
                            Write-Host ""
                            $StackError = $true
                            $ResponseCode = $_.Exception.Response.StatusCode.Value__
                            switch ($ResponseCode) {
                                404 { Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'red' | Out-Default | Write-Host; $404count++ }
                                500 { Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'yellow' | Out-Default | Write-Host; $500count++ }
                                503 { Write-Host "";Write-FormattedOutput "Installation in progress. $ResponseCode Stack $stack App $appl $url" -ForegroundColor 'yellow' | Out-Default | Write-Host; $StackError = $true; $503count++ }
                                default { Write-FormattedOutput "$ResponseCode Stack $stack App $appl $url" -ForegroundColor 'Magenta' | Out-Default | Write-Host; $defaultcount++ }
                            }
                        }

                        Write-Host ""
                    }
                }
            }
        }
        Summary

        Write-Host "$(Log-Date) Wait until application is ready before continuing"
        Write-Host "Wait at least 10 seconds to ensure that deployment has started and thus the application is offline..."
        Start-Sleep 10

        Write-GreenOutput( "Wait until Stack eval$($stack) app $appl is back online") | Write-Host
        & "$ParentDir\Wait-LansaApp.ps1" -WaitReady -Region $Region -Stack "eval$stack" -App $appl -Timeout 300
        Write-GreenOutput( "Stack eval$($stack) app $appl deployment using direct GitDeployHub $url is fully completed" )
        Write-Host
    } while ($Perpetual -and $FoundInstance)

    if ( -not $FoundInstance ) {
        $StackError = $true
        Write-RedOutput "Test failed"  | Out-Default | Write-Host
        throw "No EC2 instances found"
    }
} catch {
    $_
}
