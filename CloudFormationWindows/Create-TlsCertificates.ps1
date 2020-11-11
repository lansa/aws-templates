Param(
    [Parameter(Mandatory)]
        [string] $HostIpAddress
)

 mkdir -p C:\certs\client
 docker container run --rm `
 --env SERVER_NAME=$(hostname) `
 --env IP_ADDRESSES=127.0.0.1,$HostIpAddress `
 --volume 'C:\ProgramData\docker:C:\ProgramData\docker' `
 --volume 'C:\certs\client:C:\Users\ContainerAdministrator\.docker' `
 dockeronwindows/ch01-dockertls:2e
 Restart-Service docker

 #New-NetFirewallRule -DisplayName 'Docker SSL Inbound Insecure' -Profile @('Domain', 'Public', 'Private') -Direction Inbound -Action Allow -Protocol TCP -LocalPort 2375
 New-NetFirewallRule -DisplayName 'Docker SSL Inbound Secure' -Profile @('Domain', 'Public', 'Private') -Direction Inbound -Action Allow -Protocol TCP -LocalPort 2376

