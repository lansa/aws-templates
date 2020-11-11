# Script inspired by https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-ssl-arm

param (
    [Parameter(Mandatory=$true)]
    [String]$Region = 'uksouth',

    [Parameter(Mandatory=$true)]
    [String]$ResourceGroup = 'daftruck3',

    [Parameter(Mandatory=$true)]
    [String]$VMSSName = 'daftruck3',

    [Parameter(Mandatory=$true)]
    [String]$CertificateFilePath = 'c:\appgwcert.pfx' ,

    [Parameter(Mandatory=$true)]
    [Security.SecureString]$password
)

'AzureAG.ps1 v4'

# Remove unhelpful warnings that proliferate in the AzureRm cmdlets
$WarningPreference = "SilentlyContinue"
$VerbosePreference = "Continue"
$DebugPreference = "SilentlyContinue"

# Recreate the application gateway
$Recreate = $true

# Validate the Region
$ValidateRegion = $true

# Make non-terminating errors into terminating errors. That is, the script will throw an exception so we know its gone wrong
$ErrorActionPreference = 'Stop'

try {
    # Pre-existing Resource
    $vnetname = $vmssName + 'vnet'

    # All the rest are not dependent on existing resource names, apart from whats passed in above.
    # So names may be changed if desired
    $agsubnet = $vmssName + '-agsubnet'
    $pipname = $vmssName + '-agpip'
    $appgwName = $vmssName + '-ag'

    try {
        Write-Host( "Check parameters")

        if ( $ValidateRegion ) {
            $AllLocations = Get-AzureRmLocation
            $found = $false
            foreach ($Location in $AllLocations ) {
                if ( $location.Location -eq $Region) {
                    $found = $true
                    # Write-Host( "Location $Region must be the Display Name not the identifier. Changing to the Display Name $($location.DisplayName)" )
                    # $Region = $location.DisplayName
                    break
                }
                if ( $location.DisplayName -eq $Region){
                    $found = $true
                    Write-Host( "Location $Region must be the Identifier not the Display Name. Changing to the Identifier $($location.Location)" )
                    $Region = $location.Location
                    break
                }
            }
            if ( -not $found ) {
                Write-Host( "Location $Region does not exist" )
                throw
            }
        }

        $RG = Get-AzureRmResourceGroup -Name $ResourceGroup -Location $Region -ErrorAction "SilentlyContinue"
        if ( $null -eq $RG ) {
            Write-Host( "Resource Group $ResourceGroup does not exist" )
            throw
        }

        $VMSS = Get-AzureRmVmss -ResourceGroupName $ResourceGroup -VMScaleSetName $VMSSName -ErrorAction "SilentlyContinue"
        if ( $null -eq $VMSS ) {
            Write-Host( "VirtualMachineScaleSet $VMSSName does not exist" )
            throw
        }

        if ( -not (Test-Path -Path $CertificateFilePath) ) {
            Write-Host( "Certificate File Path $CertificateFilePath does not exist" )
            throw
        }

        $appgw = Get-AzureRmApplicationGateway `
            -Name $appgwName `
            -ResourceGroupName $ResourceGroup `
            -ErrorAction "SilentlyContinue"

        if( $Recreate ) {
            if ( $null -ne $appgw) {
                Write-Host( "Application Gateway already exists" )

                try {
                    Remove-AzureRmApplicationGateway -Name $appgwName -ResourceGroupName $ResourceGroup -force
                } catch {
                    $_
                    Write-Host( "Application Gateway $appgwName cannot be deleted. Probably because the VMSS is still using the backend pool. Make sure all targets are removed from the backend pool. Then retry")
                    exit
                }
                $appgw = $null
            }
        }
    } catch {
        $_
        Write-Host ("Invalid parameter")
        Exit
    }

    Write-Host( "Create the Application Gateway Subnet" )
    $vnet = Get-AzureRmVirtualNetwork `
        -ResourceGroupName $ResourceGroup `
        -Name $vnetname

    $subnet = Get-AzureRmVirtualNetworkSubnetConfig `
        -Name $agsubnet `
        -VirtualNetwork $vnet `
        -ErrorAction "SilentlyContinue"

    if ( $null -eq $subnet ) {
        Add-AzureRmVirtualNetworkSubnetConfig `
            -Name $agsubnet `
            -VirtualNetwork $vnet `
            -AddressPrefix "10.0.1.0/24" | Set-AzureRmVirtualNetwork
    }

    Write-Host( "Create the Application Gateway Public IP" )

    $pip = New-AzureRmPublicIpAddress `
        -ResourceGroupName $ResourceGroup `
        -Location $region `
        -Name $pipname `
        -AllocationMethod Dynamic `
        -Force

    Write-Host ( "Create the IP configurations and frontend port" )

    # The subnet id is required. This is only obtained by getting the vnet again after the subnet has been created
    $vnet = Get-AzureRmVirtualNetwork `
        -ResourceGroupName $ResourceGroup `
        -Name $vnetname

    $subnet = Get-AzureRmVirtualNetworkSubnetConfig `
        -Name $agsubnet `
        -VirtualNetwork $vnet

    $subnet | Format-List

    Write-Host ( "Associate subnet with the application gateway.")
    $gipconfigname = $vmssName + '-agIPConfig'
    $gipconfig = New-AzureRmApplicationGatewayIPConfiguration `
        -Name $gipconfigname `
        -Subnet $subnet

    Write-Host ( "Assign PublicIPAddress to the application gateway.")

    $fipconfigname = $vmssName + '-agFrontEndIPConfig'
    $fipconfig = New-AzureRmApplicationGatewayFrontendIPConfig `
        -Name $fipconfigname `
        -PublicIPAddress $pip

    Write-Host ( "Assign https port to the application gateway.")

    $frontendportname = $vmssName + '-agFrontEndPort'
    $frontendport = New-AzureRmApplicationGatewayFrontendPort `
        -Name $frontendportname `
        -Port 443

    Write-Host( "Create the backend pool and settings" )
    Write-Host( "Create the backend pool for the application gateway." )

    $AGPoolName = $vmssName + '-agPool'
    $AGPool = New-AzureRmApplicationGatewayBackendAddressPool -Name $AGPoolName

    Write-Host( "Configure the settings for the backend pool." )

    $AGPoolSettingsName = $vmssName + '-agPoolSettings'
    $AGPoolSettings = New-AzureRmApplicationGatewayBackendHttpSettings `
        -Name $AGPoolSettingsName `
        -Port 80 `
        -Protocol Http `
        -CookieBasedAffinity Enabled `
        -RequestTimeout 120

    Write-Host( "A listener is required to enable the application gateway to route traffic appropriately to the backend pool.")
    # In this example, you create a basic listener that listens for HTTPS traffic at the root URL.
    #   Create a certificate object using New-AzureRmApplicationGatewaySslCertificate and then create a listener named mydefaultListener using
    #  New-AzureRmApplicationGatewayHttpListener with the frontend configuration, frontend port, and certificate that you previously created.
    # A rule is required for the listener to know which backend pool to use for incoming traffic. Create a basic rule named rule1 using New-AzureRmApplicationGatewayRequestRoutingRule.

    Write-Host( "Upload the certificate")
    $cert = New-AzureRmApplicationGatewaySslCertificate `
        -Name $($vmssName + "appgwcert") `
        -CertificateFile $CertificateFilePath `
        -Password $password

    Write-Host( "Create the default listener")

    $defaultlistenerName = $vmssName + '-agListener'
    $defaultlistener = New-AzureRmApplicationGatewayHttpListener `
        -Name $defaultlistenerName `
        -Protocol Https `
        -FrontendIPConfiguration $fipconfig `
        -FrontendPort $frontendport `
        -SslCertificate $cert

    Write-Host( "Create the default listener rule with Backend Pool settings")

    $frontendRuleName = $vmssName + '-agRule'
    $frontendRule = New-AzureRmApplicationGatewayRequestRoutingRule `
        -Name $frontendRuleName `
        -RuleType Basic `
        -HttpListener $defaultlistener `
        -BackendAddressPool $AGPool `
        -BackendHttpSettings $AGPoolSettings

    $probe = New-AzureRmApplicationGatewayProbeConfig -Name $($VMSSName + '-probe') -Protocol Http -PickHostNameFromBackendHttpSettings -Path "/cgi-bin/probe" -Interval 30 -Timeout 120 -UnhealthyThreshold 8

    Write-Host( "Create the application gateway with the certificate. This may take 10 minutes or more")
    # Now that you created the necessary supporting resources, specify parameters for the application gateway named
    # myAppGateway using New-AzureRmApplicationGatewaySku, and then create it using New-AzureRmApplicationGateway with the certificate.

    $sku = New-AzureRmApplicationGatewaySku `
        -Name Standard_Medium `
        -Tier Standard `
        -Capacity 2

    if ( $null -eq $appgw ) {
        $appgw = New-AzureRmApplicationGateway `
            -Name $appgwName `
            -ResourceGroupName $ResourceGroup `
            -Location $Region `
            -BackendAddressPools $AGPool `
            -BackendHttpSettingsCollection $AGPoolSettings `
            -FrontendIpConfigurations $fipconfig `
            -GatewayIpConfigurations $gipconfig `
            -FrontendPorts $frontendport `
            -HttpListeners $defaultlistener `
            -RequestRoutingRules $frontendRule `
            -Sku $sku `
            -SslCertificates $cert `
            -Probes $probe
            # $appgw | Format-List | Write-Host
    }
} catch {
    $_
    Write-Host ("Fatal Error")
    Write-Host( "The message 'Generic types are not supported for input fields at this time' may mean the Location field is not valid or the Gateway already exists!")
    Exit
}
Write-Host( "Successful" )