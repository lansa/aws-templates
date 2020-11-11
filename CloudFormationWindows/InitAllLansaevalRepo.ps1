"InitAllLansaevalRepo.ps1"

push-location
set-location 'c:\lansa\lansaeval2'

$RepoStart = 200
$RepoEnd = 209
[System.Collections.ArrayList]$Repolist = @()
For ( $Repo = $RepoStart; $Repo -le $RepoEnd; $Repo++) {
    $Repolist.add($Repo) | Out-Null
}

#$Repolist.add(300) | Out-Null

foreach ( $Repo in $Repolist ) {
    #Next line only needed when first deploying from a git repo
    #git remote add lansaeval$($Repo) git@github.com:lansa/lansaeval$($Repo).git
    git remote get-url lansaeval$($Repo)
    # git push --force lansaeval$($Repo) lansaeval301_master:master
    git push --force lansaeval$($Repo)
    Write-Output( "*********************************************")
}

Pop-Location