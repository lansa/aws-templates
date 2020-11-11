# Initialise git repo related to a specific app in a specific stack

param(
[Parameter(Mandatory=$true)]
[String]$Directory
)
"GitPullForce.ps1" | Write-Host
Write-Host("cmd version = $env:comspec")
Write-Host("User = $env:userdomain\$env:username")

cmd /c exit 0 #Set $LASTEXITCODE

# Silence all errors and allow git to report them as Exit Code, then test it.
# If you set it to 'Stop', git will throw for warnings too!
# And when executing as a batch job via the scheduler, extra error messages are produced, presumably because the scheduler redirects all output to the error handle
# And some warnings return a 0 exit code, but output to the error handle
# So, silence is the best option and manually determine how to handle each command.
$ErrorActionPreference = "SilentlyContinue"

Write-Host( "Directory = $Directory")

try {
    if ( !(Test-Path $Directory) ) {
        throw "$Directory does not exist."
    }

    push-location
    set-location $Directory
    pwd | Write-Host

    Write-Host( "Getting latest changes...")
    git remote get-url origin *>&1 | Write-Host
    if ( $LASTEXITCODE -ne 0) {
        throw "git remote get-url origin LASTEXITCODE = $LASTEXITCODE"
    }

    # Fetch and Reset to the origin rather than pull in order to overwrite whatever is currently in this directory
    Git fetch *>&1 | Write-Host
    $branch = git rev-parse --abbrev-ref HEAD
    git reset --hard origin/$branch *>&1
    if ( $LASTEXITCODE -ne 0) {
        throw "git pull LASTEXITCODE = $LASTEXITCODE"
    }
} catch {
    Write-Host( "Exception")
    $_ | Write-Host
    $e = $_.Exception
    $e | format-list -force
    Write-Host( "git pull force failed" )
    Write-Host( "LASTEXITCODE $LASTEXITCODE" )
    return
} finally {
    Write-Host( 'Common completion code')
    Pop-Location
}

cmd /c exit 0 #Set $LASTEXITCODE
Write-Host( "Git pull force succeeded" )