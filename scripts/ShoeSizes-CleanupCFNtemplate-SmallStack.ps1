try{
Get-CFNStack -StackName $(stacknamesmall)
Remove-CFNStack -StackName $(stacknamesmall) -Force
$count =0
while($count -lt 20){
   try{
         Get-CFNStack -StackName $(stacknamesmall)
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

