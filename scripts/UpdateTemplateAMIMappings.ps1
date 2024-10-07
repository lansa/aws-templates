param (
    [Parameter(Mandatory=$true)]
    [string]
    [ValidateSet("Production", "Development", "Debug")]
    $ImageType
    )

If ( $ImageType -eq "Debug") {
    $FilePath = "C:\DevOps\Lansa-AWS\lansa-master-win.cfn.template"
} else {
    $FilePath = "$($env:Pipeline_Workspace)\_lansa_aws-templates\CloudFormationWindows\lansa-master-win.cfn.template"
}

$TemplateJson = Get-Content -Path $FilePath | ConvertFrom-Json

$BaseImageNameArray = @(
    'w16d-14-2'
    'w16d-15-0'
    'w19d-14-2'
    'w19d-15-0'
    'w16d-14-2j'
    'w16d-15-0j'
    'w19d-14-2j'
    'w19d-15-0j'
    'w22d-14-2'
    'w22d-15-0'
    'w22d-14-2j'
    'w22d-15-0j'

)

if ( $TemplateJson ) {

    Write-Host("JSON loaded" )

     #$TemplateJson
     $AMI142 = $TemplateJson.Mappings.AWSRegionArch2AMI142

     Write-Host( "V14 SP2 AMIs")
     $AMI142 | Out-Default | Write-Host

     $AMI15 = $TemplateJson.Mappings.AWSRegionArch2AMI15
     Write-Host( "V15 GA AMIs")
     $AMI15 | Out-Default | Write-Host

    $AMIList = @()
    $amiID = ""
    foreach ( $ImageName in $BaseImageNameArray ) {

        #Developement and Production uses same file path location
        #$path = "$($env:System_DefaultWorkingDirectory)/_Build Image Release Artefacts/aws/$ImageName.txt"
        $path = "$($env:Pipeline_Workspace)/_Build Image Release Artefacts/aws/$ImageName.txt"

        switch ($ImageType)
        {
            Development
            {
                $Region = 'ap-southeast-2'
            }
            Production
            {
                $Region = 'us-east-1'
            }
            Debug
            {
                $path = "C:\DevOps\Lansa-AWS\AMIIDS\$ImageName.txt"
                $Region = 'us-east-1'
            }
        }
        Write-Host("Path to be tested: $path")
        if ( Test-Path $path ) {
            $amiID = [string](Get-Content -Path $path)
            $AMIList += $amiID
        } else {
            Write-Host("Path does not exist.")
            $AMIList += "skip"
        }
        Clear-Variable -name path
        Clear-Variable -name amiID
    }

    Write-Host "AMI List:"
    $AMIList | Out-Default | Write-Host

    $index = 0
    foreach ($win in @(, "win2016", "win2019", "win2016jpn", "win2019jpn", "win2022", "win2022jpn")) {

        # Update the AMIs in template for Region/Win version
        if  ( $AMIList[$index] -ne "skip" ) {
            $TemplateJson.Mappings.AWSRegionArch2AMI142.$Region.$win = $AMIList[$index]
        }
        $index++
        if  ( $AMIList[$index] -ne "skip" ) {
            $TemplateJson.Mappings.AWSRegionArch2AMI15.$Region.$win = $AMIList[$index]
        }
        $index++;
    }

    $Members = Get-Member -inputobject $TemplateJson.Parameters
    foreach ( $Member in $members ) {
        if ( $Member.MemberType -eq 8 ) {  # Only Processing MemberType 8 which is Method
            $MemberName = $Member.Name

            $Description = $TemplateJson.Parameters.$MemberName.Description
            if ( $Description ) {
                $Description = $Description -replace "\\", "\\"
                $DescriptionInJson = $Description | ConvertTo-Json
                $TemplateJson.Parameters.$MemberName.Description = $DescriptionInJson.Trim('"')
            }

            $AllowedPattern = $TemplateJson.Parameters.$MemberName.AllowedPattern
            if ( $AllowedPattern ) {
                $AllowedPattern = $AllowedPattern -replace "\\\\", "\"
                $AllowedPatternInJson = $AllowedPattern | ConvertTo-Json
                $TemplateJson.Parameters.$MemberName.AllowedPattern = $AllowedPatternInJson.Trim('"')
            }
        }
    }

    $TemplateJson  | ConvertTo-Json -Depth 14 | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } | set-content $FilePath

} else {
    Throw "Template file $FilePath does not exist"
}

#goto current source folder
$path = "$($env:Pipeline_Workspace)/_lansa_aws-templates"

cd $path

# git add files
git add .
if (-not $?) {
  Write-Host("git add . failed");
  exit 1
}

$ChangedFiles = $(git status --porcelain | Measure-Object | Select-Object -expand Count)
if ($ChangedFiles -gt 0)
{
  # git commit template files
  git commit -m "Update Template AMI Mappings"
  if (-not $?) {
    Write-Host("git commit -m failed");
    exit 1
  }

  # git push to GitTargetBranch branch
  git push
  if (-not $?) {
    Write-Host("git push failed");
    exit 1
  }
}