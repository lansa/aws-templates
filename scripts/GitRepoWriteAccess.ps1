param (
    [Parameter(Mandatory=$true)]
    [string]
    $GitBranch,

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

# git configure email
git config --global user.email "$($GitUserEmail)"

# git configure name
git config --global user.name "$($GitUserName)"

# git set remote origin url with personal access token
git remote set-url origin $GitURL
