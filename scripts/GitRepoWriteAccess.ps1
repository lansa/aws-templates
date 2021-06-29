param (
    [Parameter(Mandatory=$true)]
    [string]
    $GitBranch,

    # eg: GitURL you can get it from github repo (i.e. clone https url)
    # to generate parsonal access token please follow steps mentioned in below url
    # https://docs.github.com/en/github/authenticating-to-github/keeping-your-account-and-data-secure/creating-a-personal-access-token
    # eg format for gitURL https://<Personal access token>:x-auth-basic@github.com/lansa/aws-templates.git
    [Parameter(Mandatory=$true)]
    [string]
    $GitURL,

    [Parameter(Mandatory=$true)]
    [string]
    $GitUserEmail,

    [Parameter(Mandatory=$true)]
    [string]
    $GitUserName,

    [Parameter(Mandatory=$true)]
    [string]
    $GitRepoName
  )

# goto git repo
cd "$($env:System_DefaultWorkingDirectory)/$($GitRepoName)"

# git checkout to branch
git checkout $GitBranch
if (-not $?) {
  Write-Host("git checkout $GitBranch failed");
  exit 1
}

# git configure email
git config --global user.email "$($GitUserEmail)"
if (-not $?) {
  Write-Host("git config --global user.email failed");
  exit 1
}

# git configure name
git config --global user.name "$($GitUserName)"
if (-not $?) {
  Write-Host("git config --global user.name failed");
  exit 1
}

# git set remote origin url with personal access token
git remote set-url origin $GitURL
if (-not $?) {
  Write-Host("git remote set-url failed");
  exit 1
}
