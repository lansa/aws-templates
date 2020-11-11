# Wait for a LANSA Application to be Ready or NotReady

param(
[Parameter(Mandatory=$true)]
[String]$StackName,

[Parameter(Mandatory=$true)]
[String]$App,

[Parameter(Mandatory=$true)]
[String]$Region,

[Parameter(Mandatory=$false)]
[Decimal]$Timeout = 1200,                   # Default to wait 1200 seconds = 20 mins

[Parameter(ParameterSetName='Status')]      # Continue indefinitely reporting the status
[switch]$Status,

[Parameter(ParameterSetName='WaitNotReady')]# Wait for ANY httpcode on any instance that is NOT 200
[switch]$WaitNotReady,

[Parameter(ParameterSetName='WaitReady')]   # Wait for 200 on ALL instances in stack
[switch]$WaitReady
)

"Wait-LansaApp.ps1"

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

try {
    $Perpetual = $true

    [System.Collections.ArrayList]$stacklist = @()

    $stacklist.add($StackName) | Out-Null

    $Loop = 0
    do {
        $StackError = $false
        $FoundInstance = $false
        $404count = 0
        $500count = 0
        $defaultcount = 0
        $Loop++

        # Traverse each ASG for each stack to enumerate all the instances
        # First the DB Instances then the Web Instances
        for ($j = 1; $j -le 2; $j++) {
            # Use a numbered loop so that individual stacks can be updated
            foreach ( $stack in $stacklist) {
                # Match on stack name too
                if ( $J -eq 1 ){
                    $match = "$stack-DB*"
                } else {
                    $match = "$stack-Web*"
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
                            $response = Invoke-WebRequest -Uri $url  -UseBasicParsing
                            $ResponseCode = $response.StatusCode
                        } catch {
                            if ( $WaitNotReady ) {
                                Write-Host( "Stack $StackName App $app is not ready" )
                                Exit 0
                            }
                            $ResponseCode = $_.Exception.Response.StatusCode.Value__
                            $StackError = $true
                            if ( ([string]::IsNullOrEmpty($ResponseCode) ) ) {
                                # Don't expect to throw an error if there is a null response code.
                                # Happened when running as a service with no IE configuration so output could not be parsed. Added -UseBasicParsing parameter to fix that
                                $_ | Out-Default | Write-Host
                            } else {
                                Write-FormattedOutput "$ResponseCode Stack $stack Installation in Progress $url" -ForegroundColor 'red'
                                if ( $WaitReady ) {
                                    # Waiting for an application to come up so give it some time between calls.
                                    Start-Sleep -Seconds 5
                                } else {
                                    Start-Sleep 0
                                }
                                break
                            }
                        }

                        Write-Host "$Loop $($(Get-Date).ToLocalTime()) Local Time EC2 $($Ec2Detail[0].Instances[0].InstanceId) $IPAddress" -NoNewline
                        Write-Host -NoNewline " $app"
                        try {
                            $url = "http://$IPAddress/app$app/lansaweb?w=XVLSMTST&r=GETRESPONSE&vlweb=1&part=dem&lang=ENG"
                            $response = Invoke-WebRequest -Uri $url -UseBasicParsing
                            $ResponseCode = $response.StatusCode
                            switch ($ResponseCode) {
                                200 { }
                                404 { Write-Host "";Write-FormattedOutput "$ResponseCode Stack $stack App $app $url" -ForegroundColor 'red' | Out-Host; $StackError = $true; $404count++ }
                                500 { Write-Host "";Write-FormattedOutput "$ResponseCode Stack $stack App $app $url" -ForegroundColor 'yellow' | Out-Host; $StackError = $true; $500count++ }
                                default { Write-Host "";Write-FormattedOutput"$ResponseCode Stack $stack App $app $url" -ForegroundColor 'Magenta' | Out-Host; $StackError = $true; $defaultcount++ }
                            }
                        } catch {
                            if ( $WaitNotReady ) {
                                Write-Host( "Stack $StackName App $app is not ready" )
                                Exit 0
                            }

                            Write-Host ""
                            $StackError = $true
                            $ResponseCode = $_.Exception.Response.StatusCode.Value__
                            switch ($ResponseCode) {
                                404 { Write-FormattedOutput "$ResponseCode Stack $stack App $app $url" -ForegroundColor 'red' | Out-Host; $404count++ }
                                500 { Write-FormattedOutput "$ResponseCode Stack $stack App $app $url" -ForegroundColor 'yellow' | Out-Host; $500count++ }
                                default { Write-FormattedOutput "$ResponseCode Stack $stack App $app $url" -ForegroundColor 'Magenta' | Out-Host; $defaultcount++ }
                            }
                        }
                        if ( $app -eq 1) {
                            # Workaround for IIS Plugin not coping with too many requests when first starting up
                            # First request causes all the listener connections to be setup
                            # 15 second is too short. Still get failures.
                            Start-Sleep 0
                        }
                        Write-Host ""
                    }
                }
            }
        }

        if ( $WaitReady -and (-not $StackError) ) {
            Write-Host( "Stack $StackName App $app is ready" )
            exit 0
        }

        if ( $WaitReady -or $WaitNotReady ) {
            $TimeDiff = New-TimeSpan $a
            Write-Host( "Waited $($TimeDiff.TotalSeconds) seconds so far...")
            if ( $TimeDiff.TotalSeconds -ge $Timeout) {
                throw "$Timeout second timeout has expired"
            }
            Start-Sleep 2
        } else {
            Summary
        }
    } while ($Perpetual -and $FoundInstance)

    if ( -not $FoundInstance ) {
        $StackError = $true
        Write-RedOutput "Test failed"  | Out-Host
        throw "No EC2 instances found"
    }
} catch {
    $_
    throw
}
