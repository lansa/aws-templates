param (
    [Parameter(Mandatory=$true)]
    [string]
    $Gatestack
)

try{
    Get-CFNStack -StackName $($Gatestack)
    Remove-CFNStack -StackName $($Gatestack) -Force -DeletionMode FORCE_DELETE_STACK
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

