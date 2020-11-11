# (Re)Create all evaluation stacks

Param(
    [Parameter(Mandatory)]
    [ValidateSet('Live','Test','Dev', 'All', 'Custom', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '20', '30', '40')]
    [string] $StackType
)

"CreateEvalStacks.ps1"

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
	Write-Host "$(Log-Date) Environment already initialised" | Out-Host
}

$a = Get-Date
Write-Host "$($a.ToLocalTime()) Local Time"
Write-Host "$($a.ToUniversalTime()) UTC"

[System.Collections.ArrayList]$stacklist = @()

switch ( $StackType ) {
    {$_ -eq 'Live' -or $_ -eq 'All'} {
        $GitRepoBranch = 'support/L4W14200_paas'
        $ApplMsiFolder = 'paas-live'
        $StackStart = 1
        $StackEnd = 10
        For ( $stack = $StackStart; $stack -le $StackEnd; $stack++) {
            $stacklist.add($stack) | Out-Null
        }
    }
    {$_ -eq 'Custom'} {
        $GitRepoBranch = 'support/L4W14200_paas'
        $ApplMsiFolder = 'paas-live'
        $stacklist = @(1,2,3,5,6,7,8,9,10)
    }
    {$_ -eq 'Test' -or $_ -eq 'All'} {
        $GitRepoBranch = 'patch/paas'
        $ApplMsiFolder = 'paas-test'
        $stacklist.add(20) | Out-Null
    }
    {$_ -eq 'Dev' -or $_ -eq 'All'} {
        $GitRepoBranch = 'debug/paas'
        $ApplMsiFolder = 'paas-debug'
        $stacklist.add(30) | Out-Null
    }
    # Handle numeric entry
    Default {
        $StackNum = [Decimal]$StackType
        if ( $StackNum -eq 30 -or ($StackNum -eq 40) ) {
            $GitRepoBranch = 'debug/paas'
            $ApplMsiFolder = 'paas-debug'
        } elseif ($StackNum -eq 20) {
            $GitRepoBranch = 'patch/paas'
            $ApplMsiFolder = 'paas-test'
        } else {
            $GitRepoBranch = 'support/L4W14200_paas'
            $ApplMsiFolder = 'paas-live'
        }
        $stacklist.add($StackNum) | Out-Null
    }
}

if ( $stacklist.Count -eq 0 ) {
    throw "There are no stacks requested"
}

$S3TemplateUrl = "https://lansa.s3.ap-southeast-2.amazonaws.com/templates/$GitRepoBranch/lansa-win-paas.cfn.template"
$ApplMSIUri = "https://s3.amazonaws.com/lansa-us-east-1/app/$ApplMsiFolder"
$Region = 'us-east-1'
$dbpasswordpath='c:\secrets\theman.txt'
if ($dbpasswordpath -and (Test-Path $dbpasswordpath)) {

    $password = Get-Content -Raw $dbpasswordpath
    if ($password) {
        Write-Host "Using database password from secret file: $dbpasswordpath"
    }
    else {
        throw "ERROR: no password in secret file: $dbpasswordpath"
    }
} else {
    throw "Password file $dbpasswordpath does not exist"
}

try {
    Write-Host( "Deleting & creating stacks: $($Stacklist -join ',')")
    $confirmation = Read-Host "Are you Sure You Want To Proceed (y/n):"
    if ($confirmation -ne 'y') {
        throw "aborting stack re-creation"
    }

    Write-Host( "Deleting all stacks in $stacklist")
    foreach ( $stack in $stacklist) {
        Remove-CFNStack -StackName "eval$($stack)" -region $Region -force
    }

    foreach ( $stack in $stacklist) {
        Write-Host( "Waiting up to 20 minutes for stack eval$($stack) to be deleted")
        Wait-CFNStack -StackName "eval$($stack)" -region $Region -Status 'DELETE_COMPLETE' -Timeout 1200
    }

    Write-Host( "Creating all stacks in $stacklist")

    foreach ( $stack in $stacklist) {
        New-CFNStack -StackName "eval$($stack)" -region $Region -DisableRollback $true -Parameter @( `
        @{ParameterKey="StackNumber"; ParameterValue=$stack}, `
        @{ParameterKey="03ApplCount"; ParameterValue=10}, `
        @{ParameterKey="DomainPrefix"; ParameterValue="eval$($stack)"}, `
        @{ParameterKey="03ApplMSIuri"; ParameterValue=$ApplMSIUri}, `
        @{ParameterKey="03DBUsername"; ParameterValue="themandb"}, `
        @{ParameterKey="04DBPassword"; ParameterValue=$password}, `
        @{ParameterKey="05WebUser"; ParameterValue="themanweb"},`
        @{ParameterKey="06WebPassword"; ParameterValue=$password}, `
        @{ParameterKey="07KeyName"; ParameterValue="paas_rdp"}, `
        @{ParameterKey="08RemoteAccessLocation"; ParameterValue="103.231.169.65/32"}, `
        @{ParameterKey="10LansaGitRepoBranch"; ParameterValue=$GitRepoBranch}, `
        @{ParameterKey="11WebserverOSVersion"; ParameterValue="win2016"}, `
        @{ParameterKey="21ELBTimeout"; ParameterValue=60}, `
        @{ParameterKey="12WebServerMaxConnec"; ParameterValue=10}) `
        -Capability CAPABILITY_IAM -TemplateURL $S3TemplateUrl

        Write-Host( "*********************************************")
    }

    foreach ( $stack in $stacklist) {
        Write-Host( "Waiting up to 120 minutes for stack eval$($stack) to be created")
        Wait-CFNStack -StackName "eval$($stack)" -region $Region -Status 'CREATE_COMPLETE' -Timeout 7200
    }
} catch {
    Write-Host "Aborting, maybe due to timeout"
}