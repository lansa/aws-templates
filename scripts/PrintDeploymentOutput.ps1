# Print the Deployment Output
param (
    [Parameter(Mandatory=$true)]
    [string]
    $Gatestack
)

(Get-CFNStack -StackName $($Gatestack)).Outputs[0].OutputValue | Out-Default | Write-Host


