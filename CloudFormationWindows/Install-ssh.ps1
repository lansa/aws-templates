# Refer to this article for the basis of the script: https://techcommunity.microsoft.com/t5/ITOps-Talk-Blog/Installing-and-Configuring-OpenSSH-on-Windows-Server-2019/ba-p/309540
# And ssh certificates have not been implemented. The link provides instructions on how to do that. The server I used restricted access by source ip.

# I have found it useful to add both client and server capability to Windows Server. This is also useful if the server will function a jump box. Once you’ve added the capability, you need to do a few things to get the SSH server working before you’re ready to go.
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# If you’re intending to use key based, rather than password based, authentication, you should also run the following command on the server to install an OpenSSH related PowerShell module that includes tools to help you configure that functionality
Install-Module -Force OpenSSHUtils -Scope AllUsers

# I also recommend running the following PowerShell commands on the server to install the Nano text editor, which allows you to edit text files through an SSH session or in fact cmd or powershell session. If you’re going to use key based authentication rather than passwords, you’ll need to edit one of the config files
Set-ExecutionPolicy Bypass
Iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex
choco install nano -y

# The next thing you’ll need to do on your server is to configure the disabled ssh-agent service to automatically start and also configure the sshd service to automatically start
Set-Service -Name ssh-agent -StartupType ‘Automatic’
Set-Service -Name sshd -StartupType ‘Automatic’

# And then run those services
Start-Service ssh-agent
Start-Service sshd

# Show ssh firewall rule for manual checking
Write-Host "Check that the following Firewall rule is enabled: "
Get-NetFirewallRule -Name *ssh*

# If you do all of this, you’ll be able to connect using password passed authentication from an SSH client using the syntax:
# ssh username@hostname_or_IP_address