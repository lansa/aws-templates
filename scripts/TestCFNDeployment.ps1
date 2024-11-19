# Use the deployment output to extract the IpAddress
param (
    [Parameter(Mandatory=$true)]
    [string]
    $Gatestack,

    [Parameter(Mandatory=$false)]
    [string]
    $Language='ENG',

    [Parameter(Mandatory=$false)]
    [switch]
    $DisableIntegratorTest
)

$stackoutput=(Get-CFNStack -StackName $($Gatestack)).Outputs[0].OutputValue
Write-Host "Stack Output: $stackoutput"

$IpAddress =$stackoutput

$urls = @()
$urls += "$IpAddress/cgi-bin/probe"
$urls += "$IpAddress/cgi-bin/lansaweb?about"
if($Language -eq 'JPN') {
  $urls += "$IpAddress/JPNTESTs/TEST"
  $urls += "$IpAddress/JPNTESTs/DUMMY"
} else {
  $urls += "$IpAddress/cgi-bin/lansaweb?wam=DEPTABWA&webrtn=BuildFirst&ml=LANSA:XHTML&part=DEX&lang=ENG"
  if ( -not $DisableIntegratorTest ) {
     $urls += "$IpAddress/cgi-bin/lansaweb?wam=JSMLICE&webrtn=weblic&ml=LANSA:XHTML&part=DEX&lang=ENG"
  }
}
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
$failureCount = 0
forEach($url in $urls) {
    Write-Host $url
    try{
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 60
        $ResponseCode = $response.StatusCode
        if($ResponseCode -ne 200) {
            Write-Host "Response code not equal to 200: $ResponseCode"
            $failureCount = $failureCount + 1
        } else {
            Write-Host $ResponseCode
        }
    } catch {
        $_.Exception | Out-Default | Write-Host
        $ResponseCode = $_.Exception.Response.StatusCode.Value__
        $failureCount = $failureCount + 1
        Write-Host $ResponseCode
    }
}
if($failureCount) {
    Write-Host "Request failed for $($failureCount) URL(s)"
    throw "The deployment failed the URL tests"
} else {
    Write-Host "Successfully tested all URL(s)"
}
