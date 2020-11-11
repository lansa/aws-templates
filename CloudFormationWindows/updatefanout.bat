REM Run in fanout subdirectory to update the lambda function in AWS
REM Speciy the patch in Linux format so it works in both 7zip and AWS
SET ZIPFILE=h:/temp/fanout.zip
7z a %ZIPFILE%
aws lambda update-function-code --function-name GitHubWebHookReplication --region us-east-1 --zip-file fileb://%ZIPFILE%