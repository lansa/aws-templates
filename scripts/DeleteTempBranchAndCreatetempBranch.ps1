param (
    [Parameter(Mandatory=$true)]
    [string]
    $GitBranch,

    [Parameter(Mandatory=$true)]
    [string]
    $GitRepoName
  )

# change to project directory
cd "$($env:System_DefaultWorkingDirectory)/$($GitRepoName)"

# sync with git server
git fetch
if (-not $?) {
  Write-Error ("git fetch failed");
  exit 1
}

# sync remote branches
git branch --remote
if (-not $?) {
  Write-Error ("git  branch --remote failed");
  exit 1
}

# delete git branch remote one
git push origin :$GitBranch
if (-not $?) {
  Write-Error ("git  push origin :$GitBranch failed");
  exit 1
}


# checkout temp branch
git checkout -b $GitBranch
if (-not $?) {
  Write-Error ("git  checkout -b $GitBranch failed");
  exit 1
}

# push temp branch
git push origin $GitBranch
if (-not $?) {
  Write-Error ("git push origin $GitBranch failed");
  exit 1
}

# set branch to push current one
git config --global push.default current

if (-not $?) {
  Write-Error ("git config --global push.default current failed");
  exit 1
}
