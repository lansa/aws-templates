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
cd "$($env:Pipeline_Workspace)/$($GitRepoName)"

# git checkout to branch
git checkout $GitBranch

# git configure email
git config --global user.email "$($GitUserEmail)"

# git configure name
git config --global user.name "$($GitUserName)"

# git set remote origin url with personal access token
git remote set-url origin $GitURL
