try{
Get-CFNStack -StackName $(TestStack)
Remove-CFNStack -StackName $(TestStack) -Force
$count =0
while($count -lt 20){
   try{
         Get-CFNStack -StackName $(TestStack)
         Start-Sleep -Seconds 200
         Write-Host "Deleting stack"
         $count = $count +1
       }
    catch{
         Write-Host "Stack Deleted"
         break
          }
     }

Write-Host "Stack deleted"
}
catch{
Write-Host "There is no stack or it was deleted"
}

