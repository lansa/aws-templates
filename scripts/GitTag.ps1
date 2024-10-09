param (
    [Parameter(Mandatory=$true)]
    [string]
    $GitRepoName,

    [Parameter(Mandatory=$true)]
    [string[]]
    $Tags
  )

cd "$($env:System_DeWorkinfaultgDirectory)/$($GitRepoName)"

# Change path System_DeWorkinfaultgDirectory to Pipeline_Workspace
# cd "$($env:Pipeline_Workspace)/$($GitRepoName)"

Write-Host( "Tagging the current HEAD")
git status

Write-Host( "Remove tags from the remote repo")
foreach ($tag in $Tags) {
    Write-Host ("Removing Tag $tag")
    git push origin ":refs/tags/$tag"
    # Ignore errors
}

Write-Host("git tag")
foreach ($tag in $Tags) {
    Write-Host ("Tag $tag")
    git tag -f $tag
    if (-not $?) {
      Write-Host(" git tag failed");
      exit 1
    }
}

Write-Host("git push tags")
foreach ($tag in $Tags) {
    Write-Host ("Push $tag")
    git push origin $tag
    if (-not $?) {
      Write-Host(" git push tag failed");
      exit 1
    }
}
