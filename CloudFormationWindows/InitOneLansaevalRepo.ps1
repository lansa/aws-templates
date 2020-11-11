# Initialise git repo related to a specific app in a specific stack

param(
[Parameter(Mandatory=$true)]
[String]$TargetEnvironmentUrl,

[Parameter(Mandatory=$true)]
[String]$EnvironmentName,

[Parameter(Mandatory=$false)]
[String]$Directory = 'c:\lansa\lansaeval-master'
)
"InitOneLansaevalRepo.ps1" | Write-Host

cmd /c exit 0 #Set $LASTEXITCODE

# Silence all errors and allow git to report them as Exit Code, then test it.
# If you set it to 'Stop', git will throw for warnings too!
# And when executing as a batch job via the scheduler, extra error messages are produced, presumably because the scheduler redirects all output to the error handle
# And some warnings return a 0 exit code, but output to the error handle
# So, silence is the best option and manually determine how to handle each command.
$ErrorActionPreference = "SilentlyContinue"

Write-Host( "TargetEnvironmentUrl = $TargetEnvironmentUrl")
Write-Host( "EnvironmentName = $EnvironmentName")
Write-Host( "Directory = $Directory")

try {
    if ( !(Test-Path $Directory) ) {
        throw "$Directory does not exist."
    }

    push-location
    set-location $Directory
    pwd | Write-Host

    Write-Host( "Presume latest changes have already been pulled...")
    # git remote get-url origin *>&1 | Write-Host
    # if ( $LASTEXITCODE -ne 0) {
    #     throw "git remote get-url origin LASTEXITCODE = $LASTEXITCODE"
    # }

    # # Fetch and Reset to the origin rather than pull in order to overwrite whatever is currently in this directory
    # Git fetch *>&1 | Write-Host
    # $branch = git rev-parse --abbrev-ref HEAD
    # git reset --hard origin/$branch *>&1
    # if ( $LASTEXITCODE -ne 0) {
    #     throw "git pull LASTEXITCODE = $LASTEXITCODE"
    # }

    Write-Host( "Adding a reference to the remote...")

    git remote get-url $environmentName *>&1 | Out-Null
    if ( $LASTEXITCODE -eq 128 ) {
        Write-Host( "Remote does not exist, so add it" )
        &git remote add $environmentName $TargetEnvironmentUrl *>&1 | Write-Host
        if ( $LASTEXITCODE -ne 0 ) {
            throw "git remote add $environmentName $TargetEnvironmentUrl LASTEXITCODE = $LASTEXITCODE"
        }
    } else {
        $remoteurl = git remote get-url $environmentName
        Write-Host( "Remote $EnvironmentName already configured to $Remoteurl")

        &git remote set-url $environmentName $TargetEnvironmentUrl *>&1 | Write-Host
        if ( $LASTEXITCODE -ne 0 ) {
            throw "git remote set-url $environmentName $TargetEnvironmentUrl LASTEXITCODE = $LASTEXITCODE"
        }
    }

    $remoteurl = git remote get-url $environmentName
    Write-Host( "Remote $EnvironmentName now set to $remoteurl")

    Write-Host( "Push the current branch to $TargetEnvironmentUrl...")
    git push --force $environmentName | Write-Host
    if ( $LASTEXITCODE -ne 0) {
        throw "git push --force LASTEXITCODE = $LASTEXITCODE"
    }
} catch {
    Write-Host( "Exception")
    $_ | Write-Host
    $e = $_.Exception
    $e | format-list -force
    Write-Host( "Configuration failed" )
    # cmd /c exit -1 | Write-Host    #Set $LASTEXITCODE
    Write-Host( "LASTEXITCODE $LASTEXITCODE" )
    return
} finally {
    Write-Host( 'Common completion code')
    Pop-Location
}

cmd /c exit 0 #Set $LASTEXITCODE
Write-Host( "Configuration succeeded" )