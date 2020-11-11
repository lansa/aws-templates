# Add all apps to evaluation stacks - to add them all back in with different settings
# Possibly with a change of application.msi
Param(
    [Parameter(Mandatory)]
        [ValidateSet('Live','Test','Dev','Custom')]
        [string] $StackType
)

$MyInvocation.MyCommand.Name | Out-Default | Write-Host

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
	Write-Host "$(Log-Date) Environment already initialised"
}

$a = Get-Date
Write-Host "$($a.ToLocalTime()) Local Time"
Write-Host "$($a.ToUniversalTime()) UTC"

switch ( $StackType ) {
    'Live' {
        $GitRepoBranch = 'support/L4W14200_paas'
        $S3BaseUrl = 'https://s3.amazonaws.com/lansa-us-east-1/app/paas-live'
        $StackStart = 1
        $StackEnd = 10
    }
    'Test' {
        $GitRepoBranch = 'patch/paas'
        $S3BaseUrl = 'https://s3.amazonaws.com/lansa-us-east-1/app/paas-test'
        $StackStart = 20
        $StackEnd = 20
    }
    'Dev' {
        $GitRepoBranch = 'debug/paas'
        $S3BaseUrl = 'https://s3.amazonaws.com/lansa-us-east-1/app/paas-test'
        $StackStart = 30
        $StackEnd = 30
    }
    'Custom' {
        $GitRepoBranch = 'debug/paas'
        $S3BaseUrl = 'https://s3.amazonaws.com/lansa-us-east-1/app/paas-test'
        $StackStart = 5
        $StackEnd = 5
    }
}

$ApplCount = 10
$WebserverOSVersion = 'win2016'
$WebServerMaxConnec = 10
$S3TemplateUrl = "https://lansa.s3.ap-southeast-2.amazonaws.com/templates/$GitRepoBranch/lansa-win-paas.cfn.template"
$LansaMSI = $S3BaseUrl + '/WEBSERVR_v1.0.0_en-us.msi'
$ApplMSIuri = $S3BaseUrl

$Region = 'us-east-1'
For ( $i = $StackStart; $i -le $StackEnd; $i++) {
    Write-Host("stack-name eval$($i)")

    # Stop instances being terminated whilst being updated.
    # The ASGs are left in this state. This must be changed in order for normal ASG operation to operate.
    # Running ShowLoadBalancerStatus.ps1 will set the instance back to Healthy so that the HealthCheck process
    # may be resumed.

    $ASGInstances = @(Get-ASAutoScalingInstance -Region $Region | where-object {$_.AutoScalingGroupName -like "eval$($i)-*" } )
    # $ASGInstances | Format-Table
    foreach ( $ASGInstance in $ASGInstances ) {
            Write-FormattedOutput "$($ASGInstance.AutoScalingGroupName) $($ASGInstance.InstanceId). Suspending HealthCheck process..." -ForegroundColor 'Yellow'  | Out-Host

            try {
                Suspend-ASProcess -Region $Region -AutoScalingGroupName $ASGInstance.AutoScalingGroupName -ScalingProcess @("HealthCheck", "Terminate", "ReplaceUnhealthy")
            } catch {
                $_
                Write-FormattedOutput "Error suspending HealthCheck process." -ForegroundColor 'Red'  | Out-Host
                exit
            }
    }

    aws cloudformation update-stack --stack-name eval$($i) --region $Region --capabilities CAPABILITY_IAM --template-url $S3TemplateUrl --parameters ParameterKey=03ApplCount, `
    ParameterValue=$ApplCount,UsePreviousValue=false `
    ParameterKey=11WebserverOSVersion,ParameterValue=$WebserverOSVersion,UsePreviousValue=false `
    ParameterKey=03DBUsername, UsePreviousValue=true `
    ParameterKey=04DBPassword,UsePreviousValue=true `
    ParameterKey=05WebUser,UsePreviousValue=true `
    ParameterKey=06WebPassword,UsePreviousValue=true `
    ParameterKey=07KeyName,UsePreviousValue=true `
    ParameterKey=08RemoteAccessLocation,UsePreviousValue=true `
    ParameterKey=10LansaGitRepoBranch,ParameterValue=$GitRepoBranch, UsePreviousValue=false `
    ParameterKey=11WebServerInstanceTyp,UsePreviousValue=true `
    ParameterKey=12WebServerMaxConnec,ParameterValue=$WebServerMaxConnec,UsePreviousValue=false`
    ParameterKey=13DBInstanceClass,UsePreviousValue=true `
    ParameterKey=14DBName,UsePreviousValue=true `
    ParameterKey=15DBEngine,UsePreviousValue=true `
    ParameterKey=18WebServerCapacity,UsePreviousValue=true `
    ParameterKey=19DBAllocatedStorage,UsePreviousValue=true `
    ParameterKey=20DBIops,UsePreviousValue=true `
    ParameterKey=DomainName,UsePreviousValue=true `
    ParameterKey=DomainPrefix,UsePreviousValue=true `
    ParameterKey=StackNumber,UsePreviousValue=true `
    ParameterKey=WebServerGitRepo,UsePreviousValue=true `
    ParameterKey=22AppToReinstall,UsePreviousValue=true `
    ParameterKey=22TriggerAppReinstall,UsePreviousValue=true `
    ParameterKey=22TriggerAppUpdate,ParameterValue=$ApplCount,UsePreviousValue=false `
    ParameterKey=22TriggerCakeUpdate,UsePreviousValue=true `
    ParameterKey=23TriggerChefUpdate,UsePreviousValue=true `
    ParameterKey=24TriggerWinUpdate,UsePreviousValue=true `
    ParameterKey=25TriggerWebConfig,UsePreviousValue=true `
    ParameterKey=26TriggerIcingUpdate,UsePreviousValue=true `
    ParameterKey=01LansaMSI,ParameterValue=$LansaMSI,UsePreviousValue=false `
    ParameterKey=02LansaMSIBitness,UsePreviousValue=true `
    ParameterKey=03ApplMSIuri,ParameterValue=$ApplMSIuri,UsePreviousValue=false `
    ParameterKey=17UserScriptHook,UsePreviousValue=true `
    ParameterKey=19HostRoutePortNumber,UsePreviousValue=true `
    ParameterKey=19HTTPPortNumber,UsePreviousValue=true `
    ParameterKey=19HTTPPortNumberHub,UsePreviousValue=true `
    ParameterKey=19JSMAdminPortNumber,UsePreviousValue=true `
    ParameterKey=19JSMPortNumber,UsePreviousValue=true `
    ParameterKey=21ELBTimeout,UsePreviousValue=true `
    ParameterKey=27TriggerPatchInstall,UsePreviousValue=true `
    ParameterKey=28PatchBucketName,UsePreviousValue=true `
    ParameterKey=29PatchFolderName,UsePreviousValue=true `
    ParameterKey=22TriggerAppRepoPull,UsePreviousValue=true `
    ParameterKey=SSLCertificateARN,UsePreviousValue=true   | Out-Host
    Write-Host( "*********************************************")
}
