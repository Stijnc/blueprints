::ECHO OFF
SETLOCAL

IF "%~1"=="" (
    ECHO Usage: %0 subscription-id admin-box-ip
    EXIT /B
    )

IF "%~2"=="" (
    ECHO Usage: %0 subscription-id admin-box-ip
    EXIT /B
    )

:: Set up variables to build out the naming conventions for deploying
:: the cluster

SET LOCATION=centralus
SET APP_NAME=app1
SET ENVIRONMENT=dev
SET USERNAME=testuser
SET PASSWORD=AweS0me@PW

SET NUM_VM_INSTANCES_WEB_TIER=3
SET NUM_VM_INSTANCES_BIZ_TIER=3
SET NUM_VM_INSTANCES_DB_TIER=2
SET NUM_VM_INSTANCES_MANAGE_TIER=1

SET REMOTE_ACCESS_PORT=3389

:: Explicitly set the subscription to avoid confusion as to which subscription
:: is active/default
SET SUBSCRIPTION=%1

SET ADMIN_BOX_IP=%2

:: Set up the names of things using recommended conventions
SET RESOURCE_GROUP=%APP_NAME%-%ENVIRONMENT%-rg
SET VNET_NAME=%APP_NAME%-vnet
SET PUBLIC_IP_NAME=%APP_NAME%-pip
SET BASTION_PUBLIC_IP_NAME=%APP_NAME%-bastion-pip
SET DIAGNOSTICS_STORAGE=%APP_NAME:-=%diag
SET JUMP_BOX_NIC_NAME=%APP_NAME%-manage-vm1-0nic

:: For Windows, use the following command to get the list of URNs:
:: azure vm image list %LOCATION% MicrosoftWindowsServer WindowsServer 2012-R2-Datacenter
SET WINDOWS_BASE_IMAGE=MicrosoftWindowsServer:WindowsServer:2012-R2-Datacenter:4.0.20160126

:: For a list of VM sizes see...
SET VM_SIZE=Standard_DS1

:: Set up the postfix variables attached to most CLI commands
SET POSTFIX=--resource-group %RESOURCE_GROUP% --subscription %SUBSCRIPTION%

CALL azure config mode arm

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Create resources

:: Create the enclosing resource group
CALL azure group create --name %RESOURCE_GROUP% --location %LOCATION% ^
  --subscription %SUBSCRIPTION%

:: Create the VNet
CALL azure network vnet create --address-prefixes 10.0.0.0/16 ^
  --name %VNET_NAME% --location %LOCATION% %POSTFIX%

:: Create the storage account for diagnostics logs
CALL azure storage account create --type LRS --location %LOCATION% %POSTFIX% ^
  %DIAGNOSTICS_STORAGE%

:: Create the public IP address (dynamic)
CALL azure network public-ip create --name %PUBLIC_IP_NAME% --location %LOCATION% %POSTFIX%

:: Create the management public IP address (dynamic)
CALL azure network public-ip create --name %BASTION_PUBLIC_IP_NAME% --location %LOCATION% %POSTFIX%

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Create Tiers

CALL :CreateTier web %NUM_VM_INSTANCES_WEB_TIER% 10.0.0.0/24 true
CALL :CreateTier biz %NUM_VM_INSTANCES_BIZ_TIER% 10.0.1.0/24 true
CALL :CreateTier db %NUM_VM_INSTANCES_DB_TIER% 10.0.2.0/24 false
CALL :CreateTier manage %NUM_VM_INSTANCES_MANAGE_TIER% 10.0.3.0/24 false

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: NSG Rules

:: Jump box NSG rule and public ip

SET MANAGE_NSG_NAME=%APP_NAME%-manage-nsg

azure network nsg create --name %MANAGE_NSG_NAME% --location %LOCATION% %POSTFIX%
azure network nsg rule create --nsg-name %MANAGE_NSG_NAME% --name rdp-allow ^
	--access Allow --protocol Tcp --direction Inbound --priority 100 ^
	--source-address-prefix %ADMIN_BOX_IP% --source-port-range * ^
	--destination-address-prefix * --destination-port-range %REMOTE_ACCESS_PORT% %POSTFIX%

azure network vnet subnet set --vnet-name %VNET_NAME% --name %APP_NAME%-managetier-subnet ^
	--network-security-group-name %MANAGE_NSG_NAME% %POSTFIX%

:: Make Jump Box publically accessible
CALL azure network nic set --name %JUMP_BOX_NIC_NAME% --public-ip-name %BASTION_PUBLIC_IP_NAME% %POSTFIX%


:: DB Tier NSG rule

SET DB_TIER_NSG_NAME=%APP_NAME%-dbtier-nsg

azure network nsg create --name %DB_TIER_NSG_NAME% --location %LOCATION% %POSTFIX%
azure network nsg rule create --nsg-name %DB_TIER_NSG_NAME% --name rdp-allow ^
	--access Allow --protocol Tcp --direction Inbound --priority 100 ^
	--source-address-prefix 10.0.1.0/24 --source-port-range * ^
	--destination-address-prefix * --destination-port-range * %POSTFIX%

azure network vnet subnet set --vnet-name %VNET_NAME% --name %APP_NAME%-dbtier-subnet ^
	--network-security-group-name %DB_TIER_NSG_NAME% %POSTFIX%

GOTO :eof


::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Subroutine to create a tier resources

:CreateTier

ECHO Creating %1 tier

SET TIER_NAME=%1
SET NUM_VM_INSTANCES=%2
SET ADDRESS_PREFIX=%3
SET LB_NEEDED=%4
SET SUBNET_NAME=%APP_NAME%-%TIER_NAME%tier-subnet
SET AVAILSET_TIER_NAME=%APP_NAME%-%TIER_NAME%tier-as
SET LB_NAME=%APP_NAME%-%TIER_NAME%tier-lb
SET LB_FRONTEND_NAME=%LB_NAME%-frontend
SET LB_BACKEND_NAME=%LB_NAME%-backend-pool
SET LB_PROBE_NAME=%LB_NAME%-probe

:: Create the subnet
CALL azure network vnet subnet create --vnet-name %VNET_NAME% --address-prefix ^
  %ADDRESS_PREFIX% --name %SUBNET_NAME% %POSTFIX%

IF %LB_NEEDED%==true ( 
	:: Create the load balancer
	CALL azure network lb create --name %LB_NAME% --location %LOCATION% %POSTFIX%

	IF %TIER_NAME%==web (
		ECHO Creating frontend-ip for web tier lb
		:: Associate the frontend-ip with the public IP address
		CALL azure network lb frontend-ip create --name %LB_FRONTEND_NAME% --lb-name ^
		  %LB_NAME% --public-ip-name %PUBLIC_IP_NAME% %POSTFIX%
	)

	IF %TIER_NAME%==biz (
		ECHO Creating frontend-ip for biz tier using subnet %SUBNET_NAME%
		:: Associate the frontend-ip with a private IP address
		CALL azure network lb frontend-ip create --name %LB_FRONTEND_NAME% --lb-name ^
		  %LB_NAME% --private-ip-address 10.0.1.5 --subnet-name %SUBNET_NAME% ^
		  --subnet-vnet-name %VNET_NAME% %POSTFIX%
	)

	:: Create LB back-end address pool
	CALL azure network lb address-pool create --name %LB_BACKEND_NAME% --lb-name ^
	  %LB_NAME% %POSTFIX%

	:: Create a health probe for an HTTP endpoint
	CALL azure network lb probe create --name %LB_PROBE_NAME% --lb-name %LB_NAME% ^
	  --port 80 --interval 5 --count 2 --protocol http --path / %POSTFIX%

	:: Create a load balancer rule for HTTP
	CALL azure network lb rule create --name %LB_NAME%-rule-http --protocol tcp ^
	  --lb-name %LB_NAME% --frontend-port 80 --backend-port 80 --frontend-ip-name ^
	  %LB_FRONTEND_NAME% --probe-name %LB_PROBE_NAME% %POSTFIX%
)

:: Create the availability sets
CALL azure availset create --name %AVAILSET_TIER_NAME% --location %LOCATION% %POSTFIX%

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Create VMs and per-VM resources
FOR /L %%I IN (1,1,%NUM_VM_INSTANCES%) DO CALL :CreateVM %%I %TIER_NAME% %SUBNET_NAME% %LB_NEEDED% %LB_NAME%

GOTO :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Subroutine to create the VMs and per-VM resources

:CreateVm

ECHO Creating VM %1

SET TIER_NAME=%2
SET SUBNET_NAME=%3
SET HAS_LB=%4
SET LB_NAME=%5

SET VM_NAME=%APP_NAME%-%TIER_NAME%-vm%1
SET NIC_NAME=%VM_NAME%-0nic
SET VHD_STORAGE=%VM_NAME:-=%st0
SET /a RDP_PORT=50001 + %1

SET LB_FRONTEND_NAME=%LB_NAME%-frontend
SET LB_BACKEND_NAME=%LB_NAME%-backend-pool

:: Create NIC for VM1
CALL azure network nic create --name %NIC_NAME% --subnet-name %SUBNET_NAME% ^
  --subnet-vnet-name %VNET_NAME% --location %LOCATION% %POSTFIX%

IF %HAS_LB%==true (
	:: Add NIC to back-end address pool
	CALL azure network nic address-pool add --name %NIC_NAME% --lb-name %LB_NAME% ^
	  --lb-address-pool-name %LB_BACKEND_NAME% %POSTFIX%
)

:: Create the storage account for the OS VHD
CALL azure storage account create --type PLRS --location %LOCATION% ^
 %VHD_STORAGE% %POSTFIX%

:: Create the VM
CALL azure vm create --name %VM_NAME% --os-type Windows --image-urn ^
  %WINDOWS_BASE_IMAGE% --vm-size %VM_SIZE% --vnet-subnet-name %SUBNET_NAME% ^
  --nic-name %NIC_NAME% --vnet-name %VNET_NAME% --storage-account-name ^
  %VHD_STORAGE% --os-disk-vhd "%VM_NAME%-osdisk.vhd" --admin-username ^
  "%USERNAME%" --admin-password "%PASSWORD%" --boot-diagnostics-storage-uri ^
  "https://%DIAGNOSTICS_STORAGE%.blob.core.windows.net/" --availset-name ^
  %AVAILSET_TIER_NAME% --location %LOCATION% %POSTFIX%

:: Attach a data disk
CALL azure vm disk attach-new --vm-name %VM_NAME% --size-in-gb 128 --vhd-name ^
  %VM_NAME%-data1.vhd --storage-account-name %VHD_STORAGE% %POSTFIX%

goto :eof