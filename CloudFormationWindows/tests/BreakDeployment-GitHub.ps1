# Use git pushes to deploy two different repo states alternately
# Best test is to have different VL Web runtimes in each repo
# Right now 1/4/19, changing the VL Web runtime may cause IIS to be stopped.
# Thats' fixed, but not in the Free Trial currently in the field (10321)
# Can test with different runtimes once a full test of the same runtime is
# ready to be used.

Param(
    [Parameter(Mandatory)]
        [ValidateSet('Test','Dev1','Dev2','Custom')]
        [string] $StackType
)

$MyInvocation.MyCommand.Name | Out-Default | Write-Host

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

$SeedDir = 'C:\Lansa\lansaeval2'
$FreeTrialDir = 'C:\Program Files (x86)\LANSA7'


$ParentDir = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

try {
    $Region = 'us-east-1'
    $Perpetual = $true
    [Decimal]$Stack=0
    [Decimal]$app = 2

    switch ( $StackType ) {
        'Test' {
            $Stack = 20
            $Remote = 'lansaeval200'
        }
        'Dev1' {
            $Remote = 'lansaeval302'
            $Stack = 30
            $app = 1
        }
        'Dev2' {
            $Remote = 'lansaeval301'
            $Stack = 30
        }
        'Custom' {
            $Remote = 'lansaeval302'
            $Stack = 30
        }
    }

    Write-Host "$(Log-Date) Deploying to $Remote. Alternating between $SeedDir and $FreeTrialDir"

    $Loop = 0
    do {
        $Loop++
        Write-Host
        Write-GreenOutput( "Iteration $Loop") | Write-Host
        Write-Host

        for ($k = 1; $k -le 2; $k++) {
            # Alternate between the two directories
            if ( $k -eq 1 ){
                $CurrentDir = $SeedDir
            } else {
                $CurrentDir = $FreeTrialDir
            }

            Write-Host "$(Log-Date) push the $CurrentDir git repo"
            try {
                set-location $CurrentDir
                git push --force $remote
            } catch {
                Write-Host ""
                Write-FormattedOutput "Error pushing to git repo" -ForegroundColor 'red' | Out-Default | Write-Host
                throw
            }

            Write-Host "$(Log-Date) Wait until application is ready before continuing"
            Write-Host "Wait at least 10 seconds to ensure that deployment has started and thus the application is offline..."
            Start-Sleep 10

            Write-GreenOutput( "Wait until Stack eval$($stack) app $app is back online") | Write-Host
            # Long timeout of 1200 as sometimes this script does not get a chance to deploy befpore another app is being re-installed by the other script
            & "$ParentDir\Wait-LansaApp.ps1" -WaitReady -Region $Region -Stack "eval$stack" -App $app -Timeout 1200
            Write-GreenOutput( "Stack eval$($stack) app $app deployment using $CurrentDir & remote $remote is fully completed" )
            Write-Host
        }
    } while ($Perpetual)

} catch {
    $_
}
