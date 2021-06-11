param (
    [Parameter(Mandatory=$true)]
    [string]
    [ValidateSet("Production", "Development")]
    $ImageType
    )

$FilePath = "$($env:System_DefaultWorkingDirectory)\_lansa_aws-templates\CloudFormationWindows\lansa-master-win.cfn.template"

$TemplateJson = Get-Content -Path  $FilePath | ConvertFrom-Json

$BaseImageNameArray = @(
    'w12r2d-14-2'
    'w12r2d-15-0'
    'w16d-14-2'
    'w16d-15-0'
    'w19d-14-2'
    'w19d-15-0'
    'w16d-14-2j'
    'w16d-15-0j'
    'w19d-14-2j'
    'w19d-15-0j'
)

if ( $TemplateJson ) {

    Write-Host("JSON loaded" )

    $AMI142 = $TemplateJson.Mappings.AWSRegionArch2AMI142
    Write-Host "V14 SP2 AMIs $AMI142"

    $AMI15 = $TemplateJson.Mappings.AWSRegionArch2AMI15
    Write-Host "V15 GA AMIs $AMI15"

    $AMIList = @()
    foreach ( $ImageName in $BaseImageNameArray ) {
        switch ($ImageType)
        {
            Development
            {
                $path = "$($env:System_DefaultWorkingDirectory)/_Build Image Release Artefacts/aws-$ImageName/$ImageName.txt"
                $Region = 'ap-southeast-2'
            }
            Production
            {
                $path = "$($env:System_DefaultWorkingDirectory)/copy-$ImageName.txt"
                $Region = 'us-east-1'
            }
        }

        $amiID = Get-Content -Path $path
        if ( $amiID ) {
            $AMIList += $amiID
        } else {
            $AMIList += "skip"
        }
        Clear-Variable -name path
        Clear-Variable -name amiID
    }

    $index = 0
    foreach ($win in @("win2012", "win2016", "win2019", "win2016jpn", "win2019jpn")) {
        # Check whether an AMI exists in the template for this Region/Win version
        if ( Get-Member -inputobject $AMI142 -name "$Region" ) {
            if ( Get-Member -inputobject $AMI142.$Region -name "$win" ) {
                if ( $AMIList[$index] -ne "skip") {

                    $TemplateJson.Mappings.AWSRegionArch2AMI142.$Region.$win = $AMIList[$index]
                    $index++
                }
            } else {
                Write-Host "$win V14.2 There is no AMI for $win"
            }
        } else {
            Write-Host "$win V14.2 There is no AMI in $Region"
        }

        if ( Get-Member -inputobject $AMI15 -name "$Region" ) {
            if ( Get-Member -inputobject $AMI15.$Region -name "$win") {
                if ( $AMIList[$index] -ne "skip") {
                    $TemplateJson.Mappings.AWSRegionArch2AMI15.$Region.$win = $AMIList[$index]
                    $index++
                }
            } else {
                Write-Host "$win V15 There is no AMI for $win"
            }
        } else {
            Write-Host "$win V15 There is no AMI in $Region"
        }
    }
    $TemplateJson  | ConvertTo-Json | set-content $FilePath

} else {
    Throw "Template file $FilePath does not exist"
}