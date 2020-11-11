'BreakDeployment-Reinstall.ps1'

$script:IncludeDir = $null
if ( !$script:IncludeDir)
{
    # Log-Date can't be used yet as Framework has not been loaded

	Write-Host "Initialising environment - presumed not running through RemotePS"
	$MyInvocation.MyCommand.Path
	$script:IncludeDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\scripts'
    Write-Host "Include path $script:IncludeDir"
#	. "$script:IncludeDir\Init-Baking-Vars.ps1"
#	. "$script:IncludeDir\Init-Baking-Includes.ps1"
}
else
{
	Write-Output "$(Log-Date) Environment already initialised"
}

$Reinstall = Join-Path $script:IncludeDir '..\CloudFormationWindows\ReinstallAppInStack.ps1'
for ( $loop = 1; $loop -le 999; $loop++ ) {
    & $Reinstall -Stack 30 -App 3 -SuspendStack $false
}