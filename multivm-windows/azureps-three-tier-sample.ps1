
Set-StrictMode -Version Latest

#####################################################################
# Sample script using  Azure PowerShell to build out an application 
# demonstrating a three-tier topology on Azure
#####################################################################
$LOCATION="eastus2"
$APP_NAME="profx2"
$ENVIRONMENT="prod"
$USERNAME="testuser"
$PASSWORD="AweS0me@PW"

$secpw = ConvertTo-SecureString $PASSWORD -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ($USERNAME, $secpw)

# Set up the tags to associate with items in the application
$TAG_BILLTO="InternalApp-ProFX-12345"
$Tags= @{ Name ="billTo"; Value ="$TAG_BILLTO" }

# Explicitly set the subscription to avoid confusion as to which subscription
# is active/default
$SUBSCRIPTION="3e9c25fc-55b3-4837-9bba-02b6eb204331"

# Set up the names of things using recommended conventions
$RESOURCE_GROUP="$APP_NAME-$ENVIRONMENT-rg"
$VNET_NAME="$APP_NAME-vnet"

##########################################################################################
# Set up the VM conventions for Linux and Windows images
$WINDOWS_BASE_IMAGE='MicrosoftWindowsServer:WindowsServer:2012-R2-Datacenter:4.0.20160126'
$LINUX_BASE_IMAGE='canonical:ubuntuserver:16.04.0-DAILY-LTS:16.04.201602130'


###################################################################################################
# Create resources
Get-AzureRmSubscription -SubscriptionId $SUBSCRIPTION | Select-AzureRmSubscription 

# Step 1 - create the enclosing resource group
New-AzureRmResourceGroup -Name $RESOURCE_GROUP -Location $LOCATION -Tag $Tags -Verbose

# Step 3 - create the networks (VNet and subnets)
$vnet = New-AzureRmVirtualNetwork -Name $VNET_NAME -ResourceGroupName $RESOURCE_GROUP `
    -AddressPrefix "10.0.0.0/8" -Location $LOCATION -Tag $Tags -Verbose
Add-AzureRmVirtualNetworkSubnetConfig -Name fe-subnet -VirtualNetwork $vnet -AddressPrefix "10.0.1.0/24"
Add-AzureRmVirtualNetworkSubnetConfig -Name es-master-subnet -VirtualNetwork $vnet -AddressPrefix "10.0.2.0/24"
Add-AzureRmVirtualNetworkSubnetConfig -Name es-data-subnet -VirtualNetwork $vnet -AddressPrefix "10.0.3.0/24"
Add-AzureRmVirtualNetworkSubnetConfig -Name sql-subnet -VirtualNetwork $vnet -AddressPrefix "10.0.4.0/24"
Add-AzureRmVirtualNetworkSubnetConfig -Name mgmt-subnet -VirtualNetwork $vnet -AddressPrefix "10.0.5.0/24"

# Note - the commands above only updated the VNET configuration.  The changes do not
# take effect until we update the actual VNET configuration in Azure.
Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
$vnet = Get-AzureRmVirtualNetwork -Name $VNET_NAME -ResourceGroupName $RESOURCE_GROUP

# Step 4 - define the load balancer and network security rules

# Step 4.1 - Create the load balancer, public IP and frontend IP 
New-AzureRmPublicIpAddress -Name "$APP_NAME-lb-pip" -ResourceGroupName $RESOURCE_GROUP `
    -Location $LOCATION –AllocationMethod Static -DomainNameLabel $APP_NAME -Verbose
$publicIP = Get-AzureRmPublicIpAddress -Name "$APP_NAME-lb-pip" -ResourceGroupName $RESOURCE_GROUP 
   
$frontendIP = New-AzureRmLoadBalancerFrontendIpConfig -Name "$APP_NAME-lb" `
    -PublicIpAddress $publicIP

# Step 4.2 - Create the load balancer address pool and obtain the 
# ID of the load balancer address pool (for use when creating NICs)
$backendPool = New-AzureRmLoadBalancerBackendAddressPoolConfig `
    -Name "$APP_NAME-lb-address-pool"

$healthProbe = New-AzureRmLoadBalancerProbeConfig -Name "$APP_NAME-lb-probe" `
    -RequestPath '/' -Protocol http -Port 80 -IntervalInSeconds 15 -ProbeCount 2

# 4.3 - Create the forwarding rule and health probe
$lbrule = New-AzureRmLoadBalancerRuleConfig -Name "$APP_NAME-web-rule"  `
    -FrontendIpConfiguration $frontendIP -BackendAddressPool $backendPool `
    -Probe $healthProbe -Protocol Tcp -FrontendPort 80 -BackendPort 80

# 4.4 - using the load balancer configuration generated above, create the load
# balancer
New-AzureRmLoadBalancer -Name "$APP_NAME-lb" `
    -FrontendIpConfiguration $frontendIP -BackendAddressPool $backendPool `
    -LoadBalancingRule $lbrule -Probe $healthProbe `
    -ResourceGroupName $RESOURCE_GROUP  -Location $LOCATION 
$lb = Get-AzureRmLoadBalancer -Name "$APP_NAME-lb" -ResourceGroupName $RESOURCE_GROUP

# TODO - enable diagnostics for load balancer
# Set-AzureRmDiagnosticSetting  -ResourceId /subscriptions/<subscription_id>/resourceGroups/<rg name>/providers/Microsoft.Network/applicationGateways/<appgw name> -StorageAccountId /subscriptions/<sub_id>/resourceGroups/<rg name>/providers/Microsoft.Storage/storageAccounts/<storage account name> -Enabled $true  

# Step 5 - create a diagnostics storage account
$diagnostics_storage_account=("$APP_NAME" -replace '-') + 'diag'
New-AzureRmStorageAccount -Name $diagnostics_storage_account `
    -Type Standard_LRS -Location $LOCATION -ResourceGroupName $RESOURCE_GROUP `
    -Tags $Tags -Verbose
$diagAccount = Get-AzureRmStorageAccount -Name $diagnostics_storage_account `
    -ResourceGroupName $RESOURCE_GROUP

# Step 6.1 - Create the gateway VMs and add them to the address pool for the load balancer
$gwAvailSet = New-AzureRmAvailabilitySet -Name "$APP_NAME-fe-as" `
    -ResourceGroupName $RESOURCE_GROUP -Location $LOCATION
for ($i = 1; $i -le 4; i++)
{
    Create-VM "$APP_NAME-gw$i" $vnet.Subnets[0] 'Windows' $WINDOWS_BASE_IMAGE `
        'Standard_DS1' $diagnostics_storage_account "$APP_NAME-fe-as" 
    Add-VirtualMachine-ToLoadBalancerPool "$APP_NAME-gw$i" $lb "$APP_NAME-lb-address-pool" 
}

# Step 7 - Create the jump box, with a public IP address
Create-VM "$APP_NAME-jumpbox" $vnet.Subnets[4] "Windows" "$WINDOWS_BASE_IMAGE" `
    "Standard_DS1" "$diagnostics_storage_account"
$publicIPJumpbox = New-AzureRmPublicIpAddress -Name "$APP_NAME-bastion-pip" `
    -ResourceGroupName $RESOURCE_GROUP -Location $LOCATION –AllocationMethod Dynamic `
    -DomainNameLabel "$APP_NAME-bastion" -Verbose
$jumpNic = Get-AzureRmNetworkInterface -Name "$APP_NAME-jumpbox-0nic" `
    -ResourceGroupName $RESOURCE_GROUP
$jumpNic.IpConfigurations[0].PublicIpAddress = $publicIPJumpbox
Set-AzureRmNetworkInterface -NetworkInterface $jumpNic


function Add-VirtualMachine-ToLoadBalancerPool
(
    [string] $VmName,    
    [Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $loadBalancer,
    [string] $poolName
)
{
    $be = Get-AzureRmLoadBalancerBackendAddressPoolConfig -Name $poolName `
        -LoadBalancer $loadBalancer 

    $vm = Get-AzureRmVM -Name $VmName -ResourceGroupName $RESOURCE_GROUP
    $nicName = $vm.NetworkInterfaceIDs[0].Split('/')[-1]    
    $nic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $RESOURCE_GROUP

    $nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $be
    Set-AzureRmNetworkInterface -NetworkInterface $nic
}

function Create-VM
(
    [string] $VmName,    
    [Microsoft.Azure.Commands.Network.Models.PSSubnet] $Subnet,
    [string] $OsType,
    [string] $ImageUrn,
    [string] $VmSize,
    [string] $DiagnosticsStorage,
    [string] $AvailabilitySetName    
)
{
    # Create the NIC for this VM    
    $nic = New-AzureRmNetworkInterface -Name "$VmName-0nic" -Subnet $Subnet `
        -ResourceGroupName $RESOURCE_GROUP -Location $LOCATION 

    # Create the storage account for this vm's disks (premium locally redundant storage -> PLRS)    
    $storage_account_name=($VmName -replace '-') + "st01"
    $diskAccount = New-AzureRmStorageAccount -Name $storage_account_name `
        -Type Premium_LRS -Location $LOCATION -ResourceGroupName $RESOURCE_GROUP `
        -Tags $Tags
	
    if ( [string]::IsNullOrEmpty($AvailabilitySetName) ) {
        $vm = New-AzureRmVMConfig -VMName $VmName -VMSize $VmSize 
    }
    else {
        $availSet = Get-AzureRmAvailabilitySet -Name $AvailabilitySetName -ResourceGroupName $RESOURCE_GROUP
        $vm = New-AzureRmVMConfig -VMName $VmName -VMSize $VmSize `
            -AvailabilitySetId $availSet.Id
    }    
    
    # Set the operating system configuration
    If ($OsType -eq 'Windows') {
        $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmName `
            -Credential $creds -ProvisionVMAgent -EnableAutoUpdate
    } ElseIf ($OsType -eq 'Linux') {
        $vm = Set-AzureRmVMOperatingSystem -VM $vm -Linux -ComputerName $vmName `
            -Credential $creds 
    }
    Else {
        # TODO - throw error
    }
     
    # Break the image URN down into its components, and set the source image details
    $pieces = $ImageUrn.Split(':')
    $vm = Set-AzureRmVMSourceImage -VM $vm `
        -PublisherName $pieces[0] -Offer $pieces[1] -Skus $pieces[2] -Version $pieces[3]
    
    # Attach the NIC
    $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id

    # Configure the OS disk
    $diskName = $VmName + "-osdisk"
    $osDiskUri = $diskAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $diskName + ".vhd"
    Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption fromImage

    # Configure Boot Diagnostics
    Set-AzureRmVMBootDiagnostics -VM $vm -Enable -ResourceGroupName $RESOURCE_GROUP  `
        -StorageAccountName $DiagnosticsStorage

    # Create the virtual machine
    New-AzureRmVM -VM $vm -ResourceGroupName $RESOURCE_GROUP -Location $LOCATION 
}

