param (
    [Parameter(Mandatory=$true)]
    [string]
    $Gatestack
)

try{
    Get-CFNStack -StackName $($Gatestack)
    # Documentation says that there is a  -DeletionMode parameter, but it throws an error saying the parameter does not exist
    Remove-CFNStack -StackName $($Gatestack) -Force
    $count =0
    while($count -lt 20){
        try{
            Get-CFNStack -StackName $($Gatestack)
            Start-Sleep -Seconds 200
            Write-Host "Deleting stack"
            $count = $count +1
        } catch {
            Write-Host "Stack Deleted"
            break
        }
    }
    Write-Host "Stack deleted"
} catch {
    $_.Exception.Message | Out-Default | Write-Host
    Write-Host "Stack does not exist or is already deleted"
}

