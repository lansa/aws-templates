# Print the Deployment Output
param (
    [Parameter(Mandatory=$true)]
    [string]
    $Gatestack
)

$stackoutput=(Get-CFNStack -StackName $($Gatestack)).Outputs[0].OutputValue
Write-Host $stackoutput

