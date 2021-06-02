# Print the Deployment Output
$stackoutput=(Get-CFNStack -StackName $(Gate.stack)).Outputs[0].OutputValue
Write-Host $stackoutput

