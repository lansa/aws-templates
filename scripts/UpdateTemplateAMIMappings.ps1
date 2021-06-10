param (
    [Parameter(Mandatory=$true)]
    [string]
    [ValidateNotNull()]
    $TemplateUrl,

    [Parameter(Mandatory=$true)]
    [string]
    $ImageType
)

Write-Host "TemplateURL: $TemplateUrl and ImageType: $ImageType"
# Ensures that Invoke-WebRequest uses TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$TemplateJson = Invoke-WebRequest $TemplateUrl | ConvertFrom-Json

$BaseImageNameArray = @(
    'w12r2d-14-2'
    'w12r2d-15-0'
    'w16d-14-2'
    'w16d-15-0'
    'w19d-14-2'
    'w19d-15-0'
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

    foreach ( $ImageName in $BaseImageNameArray ) {
        Clear-Variable -name path
        if ( $ImageType -eq "Development" ) {
            $path = "$($env:System_DefaultWorkingDirectory)/_Build Image Release Artefacts/aws-$ImageName/$ImageName.txt"
            $region = "ap-southeast-2"
        } elseif ( $ImageType -eq "Production" ) {
            $path = "$($env:System_DefaultWorkingDirectory)/copy-$ImageName.txt"
            $region = "us-east-1"
        } else {
            Write-Host "ImageType $ImageType is not supported"
        }
        $amiID = Get-Content -Path $path
        
        #Update Template file based on amiID read from the file above.
    }
}