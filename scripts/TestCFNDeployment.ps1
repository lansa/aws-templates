# Use the deployment output to extract the IpAddress
param (
    [Parameter(Mandatory=$true)]
    [string]
    $Gatestack
)

$stackoutput=(Get-CFNStack -StackName $($Gatestack)).Outputs[0].OutputValue
#Write-Host $stackoutput

$IpAddress =$stackoutput

$url1 = "$IpAddress/cgi-bin/probe"
$url2 = "$IpAddress/cgi-bin/lansaweb?about"
$url3 = "$IpAddress/cgi-bin/lansaweb?wam=DEPTABWA&webrtn=BuildFirst&ml=LANSA:XHTML&part=DEX&lang=ENG"
$url4 = "$IpAddress/cgi-bin/lansaweb?wam=JSMLICE&webrtn=weblic&ml=LANSA:XHTML&part=DEX&lang=ENG"
$urls = @($url1, $url2, $url3, $url4)
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
    try{
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 14
        $ResponseCode = $response.StatusCode
        if($ResponseCode -ne 200) {
            Write-Host "Response code not equal to 200: $ResponseCode"
            $failureCount = $failureCount + 1
        } else {
            Write-Host $url
            Write-Host $ResponseCode
        }
    } catch {
        Write-Host $_.Exception
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

