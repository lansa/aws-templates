# Reinstall a specific set of apps
"ReinstallSpecificApps.ps1"

$script:IncludeDir = $null
if ( !$script:IncludeDir)
{
    # Log-Date can't be used yet as Framework has not been loaded

	Write-Host "Initialising environment - presumed not running through RemotePS"
	$MyInvocation.MyCommand.Path
	$script:IncludeDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\scripts'
	$script:InvocationDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Write-Host "Include path $script:IncludeDir"
	. "$script:IncludeDir\Init-Baking-Vars.ps1"
	. "$script:IncludeDir\Init-Baking-Includes.ps1"
}
else
{
	Write-Output "$(Log-Date) Environment already initialised" | Out-Host
}

$a = Get-Date
Write-Host "$($a.ToLocalTime()) Local Time"
Write-Host "$($a.ToUniversalTime()) UTC"

try {
    do {
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 2
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 1
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 3
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 4
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 5
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 6
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 7
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 8
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 9
        & "$script:InvocationDir\ReinstallAppInStack.ps1" -Stack 30 -App 10
    } while ( $true )
} catch {
    $_
    throw
}