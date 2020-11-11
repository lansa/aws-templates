# Reinstall a specific app in stack

param(
[Parameter(Mandatory=$true)]
[Decimal]$Stack,

[Parameter(Mandatory=$true)]
[Decimal]$App,

[Parameter(Mandatory=$false)]
[boolean]$SuspendStack = $true
)

"ReinstallAppInStack.ps1"

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
	Write-Output "$(Log-Date) Environment already initialised" | Write-Host
}

$a = Get-Date
Write-Host "$($a.ToLocalTime()) Local Time"
Write-Host "$($a.ToUniversalTime()) UTC"

# Generate random  number to ensure (almost) a difference when updating the stack
$Random = Get-Random
try {
    if ($Stack -lt 1 -or ($Stack -gt 40)) {
        throw "Stack number $stack is not between 1 and 40"
    }

    if ($App -lt 1 -or ($App -gt 10)) {
        throw "Application number $app is not between 1 and 10"
    }

    $Region = 'us-east-1'

    Write-GreenOutput( "Only allow one execution of this script at a time, this allows multiple stacks to be requested to be updated and they will wait here, if there is already an operation occurring on that stack, until the previous script has completed...") | Write-Host
    $Mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, "Global\ReinstallAppInStack$Stack"
    if ( -not $Mutex ) {
        throw "Failed to create mutex"
    }

    # Wait 60 mins for exclusive access to the mutex
    if ( -not $Mutex.WaitOne(3600*1000) ) {
        $Mutex = $null
        throw "Timed out waiting for exclusive access to ReinstallAppInStack script"
    }

    if ( $SuspendStack ) {
        & (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "SuspendStack.ps1") -Stack $Stack
    }

    Write-GreenOutput( "$(Get-Date) Re-installing Application $App in stack $stack") | Write-Host

    aws cloudformation update-stack --stack-name eval$($stack) --region $Region --capabilities CAPABILITY_IAM --use-previous-template `
    --parameters ParameterKey=03ApplCount,UsePreviousValue=true ParameterKey=03DBUsername,UsePreviousValue=true ParameterKey=04DBPassword,UsePreviousValue=true ParameterKey=05WebUser,UsePreviousValue=true ParameterKey=06WebPassword,UsePreviousValue=true ParameterKey=07KeyName,UsePreviousValue=true ParameterKey=08RemoteAccessLocation,UsePreviousValue=true ParameterKey=10LansaGitRepoBranch,UsePreviousValue=true ParameterKey=11WebServerInstanceTyp,UsePreviousValue=true ParameterKey=11WebserverOSVersion,UsePreviousValue=true ParameterKey=12WebServerMaxConnec,UsePreviousValue=true ParameterKey=13DBInstanceClass,UsePreviousValue=true ParameterKey=14DBName,UsePreviousValue=true ParameterKey=15DBEngine,UsePreviousValue=true ParameterKey=18WebServerCapacity,UsePreviousValue=true ParameterKey=19DBAllocatedStorage,UsePreviousValue=true ParameterKey=20DBIops,UsePreviousValue=true ParameterKey=DomainName,UsePreviousValue=true ParameterKey=DomainPrefix,UsePreviousValue=true ParameterKey=StackNumber,UsePreviousValue=true ParameterKey=WebServerGitRepo,UsePreviousValue=true `
    ParameterKey=22AppToReinstall,UsePreviousValue=false,ParameterValue=$App `
    ParameterKey=22TriggerAppRepoPull,UsePreviousValue=true `
    ParameterKey=22TriggerAppReinstall,UsePreviousValue=false,ParameterValue=$Random `
    ParameterKey=22TriggerAppUpdate,UsePreviousValue=true ParameterKey=22TriggerCakeUpdate,UsePreviousValue=true ParameterKey=23TriggerChefUpdate,UsePreviousValue=true ParameterKey=24TriggerWinUpdate,UsePreviousValue=true ParameterKey=25TriggerWebConfig,UsePreviousValue=true ParameterKey=26TriggerIcingUpdate,UsePreviousValue=true ParameterKey=01LansaMSI,UsePreviousValue=true ParameterKey=02LansaMSIBitness,UsePreviousValue=true ParameterKey=03ApplMSIuri,UsePreviousValue=true ParameterKey=17UserScriptHook,UsePreviousValue=true ParameterKey=19HostRoutePortNumber,UsePreviousValue=true ParameterKey=19HTTPPortNumber,UsePreviousValue=true ParameterKey=19HTTPPortNumberHub,UsePreviousValue=true ParameterKey=19JSMAdminPortNumber,UsePreviousValue=true ParameterKey=19JSMPortNumber,UsePreviousValue=true ParameterKey=21ELBTimeout,UsePreviousValue=true ParameterKey=27TriggerPatchInstall,UsePreviousValue=true ParameterKey=28PatchBucketName,UsePreviousValue=true ParameterKey=29PatchFolderName,UsePreviousValue=true ParameterKey=SSLCertificateARN,UsePreviousValue=true | Out-Default | Write-Host
    Write-Host( "*********************************************")
    Write-GreenOutput( "$(Get-Date) Note that the trace settings are not specified, as at the time these were new parameters and the default is to not trace which seems appropriate") | Write-Host
    if ( $LASTEXITCODE -ne 0 ) {
        throw
    }

    Write-Host( "Waiting up to 10 minutes for template changes to be applied to stack eval$($stack)")
    Wait-CFNStack -StackName "eval$($stack)" -region $Region -Timeout 600 | Out-Default | Write-Host
    $stackobject = get-cfnstack "eval$($stack)" -region $Region
    if ($stackobject.StackStatus -ne 'UPDATE_COMPLETE') {
        throw "Stack update failed"
    }

    Write-Host( "Check if the update was successful")


    # Wait for application to NOT be ready before checking its back online
    Write-GreenOutput( "Wait until Stack eval$($stack) app $app is NOT ready before checking if its back online") | Write-Host
    & "$script:InvocationDir\Wait-LansaApp.ps1" -WaitNotReady -Region $Region -Stack "eval$stack" -App $app -Timeout 300

    # Write-Host( "$(Get-Date) Wait for 10 minutes so that no activity is occurring whilst install is occurring...")
    # Start-Sleep -S 600

    Write-GreenOutput( "Wait until Stack eval$($stack) app $app is back online") | Write-Host
    & "$script:InvocationDir\Wait-LansaApp.ps1" -WaitReady -Region $Region -Stack "eval$stack" -App $app -Timeout 1200

    if ( $SuspendStack ) {
        & (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "ResumeStack.ps1") -Stack $Stack
    }

    Write-GreenOutput( "Stack eval$($stack) app $app reinstall is fully completed" ) | Write-Host
} catch {
    Write-Host( "Exception")
    $_ | Out-Default | Write-Host
    Write-Host ("If the error is 'An error occurred (ValidationError) when calling the UpdateStack operation: No updates are to be performed.', its because the previous application updated in this stack is the same one - there are no changes.") | Write-Host
    throw
    $e = $_.Exception
    $e | format-list -force | Out-Default | Write-Host
    Write-Host( "Configuration failed" )
    cmd /c exit -1 | Out-Default | Write-Host    #Set $LASTEXITCODE
    Write-Host( "LASTEXITCODE $LASTEXITCODE" )
    return
} finally {
    if ( $Mutex ) {
        $Mutex.ReleaseMutex()
    }
}

cmd /c exit 0 #Set $LASTEXITCODE
