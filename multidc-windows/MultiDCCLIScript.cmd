::@ECHO OFF
SETLOCAL

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Set up variables for deploying resources to Azure.
:: Change these variables for your own deployment

:: The APP_NAME variable must not exceed 4 characters in size.
:: If it does the 15 character size limitation of the VM name may be exceeded.
SET APP_NAME=app2
SET LOCATION=centralus
SET FAILOVER_LOCATION=eastus
SET ENVIRONMENT=dev
SET USERNAME=testuser

SET VNET_IP_RANGE=10.0.0.0/16

:: For Windows, use the following command to get the list of URNs:
:: azure vm image list %LOCATION% MicrosoftWindowsServer WindowsServer 2012-R2-Datacenter
SET WINDOWS_BASE_IMAGE=MicrosoftWindowsServer:WindowsServer:2012-R2-Datacenter:4.0.20160126

:: For a list of VM sizes see: https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-size-specs/
:: To see the VM sizes available in a region:
:: 	azure vm sizes --location <<location>>
SET VM_SIZE=Standard_DS1

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

IF "%3"=="" (
    ECHO Usage: %0 subscription-id admin-address-whitelist-CIDR-format admin-password
    ECHO   For example: %0 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx nnn.nnn.nnn.nnn/mm pwd
    EXIT /B
    )

:: Explicitly set the subscription to avoid confusion as to which subscription
:: is active/default

SET SUBSCRIPTION=%1
SET ADMIN_ADDRESS_PREFIX=%2
SET PASSWORD=%3

:: Set up the names of things using recommended conventions
SET RESOURCE_GROUP=%APP_NAME%-%ENVIRONMENT%-rg
SET TRAFFICMANAGERPROFILE_NAME=%APP_NAME%-%ENVIRONMENT%-tm
SET TRAFFICMANAGERPROFILE_DNSNAME=%APP_NAME%%ENVIRONMENT%
SET TRAFFICMANAGERPROFILE_MONITORPATH=/healthprobe/index/123

SET VNET_NAME=%APP_NAME%-vnet
SET PUBLIC_IP_NAME=%APP_NAME%-pip
SET FAILOVERPUBLIC_IP_NAME=%APP_NAME%-failover-pip
SET DIAGNOSTICS_STORAGE=%APP_NAME:-=%diag
SET JUMPBOX_PUBLIC_IP_NAME=%APP_NAME%-jumpbox-pip
SET JUMPBOX_NIC_NAME=%APP_NAME%-manage-vm1-nic1

:: Set up the postfix variables attached to most CLI commands
SET POSTFIX=--resource-group %RESOURCE_GROUP% --subscription %SUBSCRIPTION%

CALL azure config mode arm


::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Create root level resources

:: Create the enclosing resource group
CALL azure group create --name %RESOURCE_GROUP% --location %LOCATION% ^
  --subscription %SUBSCRIPTION%

:: Create the virtual network
CALL azure network vnet create --address-prefixes %VNET_IP_RANGE% ^
  --name %VNET_NAME% --location %LOCATION% %POSTFIX%

:: Create the public IP address (dynamic)
CALL azure network public-ip create --name %PUBLIC_IP_NAME% ^
  --location %LOCATION% --domain-name-label %PUBLIC_IP_NAME% %POSTFIX%

:: Create the failover public IP address (dynamic)
CALL azure network public-ip create --name %FAILOVERPUBLIC_IP_NAME% ^
  --location %FAILOVER_LOCATION% --domain-name-label %FAILOVERPUBLIC_IP_NAME% %POSTFIX%

CALL azure network traffic-manager profile create ^
  --name %TRAFFICMANAGERPROFILE_NAME% ^
  --relative-dns-name %TRAFFICMANAGERPROFILE_DNSNAME% ^
  --monitor-path %TRAFFICMANAGERPROFILE_MONITORPATH% %POSTFIX%

SET PUBLIC_IP_RESOURCEID=/subscriptions/%SUBSCRIPTION%/resourceGroups/%RESOURCE_GROUP%/providers/Microsoft.Network/publicIPAddresses/%PUBLIC_IP_NAME%
SET FAILOVERPUBLIC_IP_RESOURCEID=/subscriptions/%SUBSCRIPTION%/resourceGroups/%RESOURCE_GROUP%/providers/Microsoft.Network/publicIPAddresses/%FAILOVERPUBLIC_IP_NAME%

CALL azure network traffic-manager endpoint create ^
  --name %TRAFFICMANAGERPROFILE_NAME%-ep-%LOCATION% ^
  --profile-name %TRAFFICMANAGERPROFILE_NAME% ^
  --type AzureEndpoints ^
  --target-resource-id %PUBLIC_IP_RESOURCEID%  %POSTFIX%

CALL azure network traffic-manager endpoint create ^
  --name %TRAFFICMANAGERPROFILE_NAME%-ep-%FAILOVER_LOCATION% ^
  --profile-name %TRAFFICMANAGERPROFILE_NAME% ^
  --type AzureEndpoints ^
  --target-resource-id %FAILOVERPUBLIC_IP_RESOURCEID%  %POSTFIX%
