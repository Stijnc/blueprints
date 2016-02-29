#!/bin/sh

#####################################################################
# Sample script using the Azure CLI to build out an application 
# demonstrating a three-tier topology on Azure
#####################################################################
# TODO - load balancer rules are not allowing inbound traffic
# TODO - network diagnostics are not enabled by default
# TODO - storage diagnostics are not enabled

# Set up variables to build out the naming conventions for deploying
# the cluster
LOCATION=eastus2
APP_NAME=profx
ENVIRONMENT=prod
USERNAME=testuser
PASSWORD="AweS0me@PW"

# Set up the tags to associate with items in the application
TAG_BILLTO="InternalApp-ProFX-12345"
TAGS="billTo=${TAG_BILLTO}"

# Explicitly set the subscription to avoid confusion as to which subscription
# is active/default
SUBSCRIPTION=3e9c25fc-55b3-4837-9bba-02b6eb204331

# Set up the names of things using recommended conventions
RESOURCE_GROUP="${APP_NAME}-${ENVIRONMENT}-rg"
VNET_NAME="${APP_NAME}-vnet"

# Set up the postfix variables attached to most CLI commands
POSTFIX="--resource-group ${RESOURCE_GROUP} --location ${LOCATION} --subscription ${SUBSCRIPTION}"

##########################################################################################
# Set up the VM conventions for Linux and Windows images

# For Windows, get the list of URN's via 
# azure vm image list ${LOCATION} MicrosoftWindowsServer WindowsServer 2012-R2-Datacenter
WINDOWS_BASE_IMAGE=MicrosoftWindowsServer:WindowsServer:2012-R2-Datacenter:4.0.20160126

# For Linux, get the list or URN's via 
# azure vm image list ${LOCATION} canonical ubuntuserver
LINUX_BASE_IMAGE=canonical:ubuntuserver:16.04.0-DAILY-LTS:16.04.201602130

#########################################################################################
## Define functions 
create_vm ()
{
    vm_name=$1
    vnet_name=$2
    subnet_name=$3
    os_type=$4
    vhd_path=$5
    vm_size=$6
    diagnostics_storage=$7
    availset=$8

    if [ -n "$availset" ]; then
        echo "Creating vm ${vm_name} in availability set ${availset}"
        AVAIL_SET=" --availset-name ${availset}"
    else
        AVAIL_SET=""
    fi

	# Create the network interface card for this VM
	azure network nic create --name "${vm_name}-0nic" --subnet-name ${subnet_name} --subnet-vnet-name ${vnet_name} \
        --tags="${TAGS}" ${POSTFIX}

	# Create the storage account for this vm's disks (premium locally redundant storage -> PLRS)
    # Note the ${var//-/} syntax to remove dashes from the vm name
    storage_account_name=${vm_name//-/}st01
	azure storage account create --type=PLRS --tags "${TAGS}" ${POSTFIX} "${storage_account_name}"

    # Map the name of the diagnostics storage account to a blob URI for boot diagnostics
    # This is (currently) required when deploying with a named premium storage account 
    diag_blob="https://${diagnostics_storage}.blob.core.windows.net/"

    # Create the VM
    azure vm create --name ${vm_name} --nic-name "${vm_name}-0nic" --os-type ${os_type} \
        --image-urn ${vhd_path} --vm-size ${vm_size} --vnet-name ${vnet_name} --vnet-subnet-name ${subnet_name} \
        --storage-account-name "${storage_account_name}" --storage-account-container-name vhds --os-disk-vhd "${vm_name}-osdisk.vhd" \
        --admin-username "${USERNAME}" --admin-password "${PASSWORD}" \
		--boot-diagnostics-storage-uri "${diag_blob}" \
        ${AVAIL_SET} \
        --tags="${TAGS}" ${POSTFIX} 
}

###################################################################################################
# Create resources

# Step 1 - create the enclosing resource group
azure group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --tags "${TAGS}" --subscription "${SUBSCRIPTION}"

# Step 2 - create the network security groups

# Step 3 - create the networks (VNet and subnets)
azure network vnet create --name "${VNET_NAME}" --address-prefixes="10.0.0.0/8" --tags "${TAGS}" ${POSTFIX}
azure network vnet subnet create --name fe-subnet --vnet-name "${VNET_NAME}" --address-prefix="10.0.1.0/24" --resource-group "${RESOURCE_GROUP}" --subscription ${SUBSCRIPTION}
azure network vnet subnet create --name es-master-subnet --vnet-name "${VNET_NAME}" --address-prefix="10.0.2.0/24" --resource-group "${RESOURCE_GROUP}" --subscription ${SUBSCRIPTION}
azure network vnet subnet create --name es-data-subnet --vnet-name "${VNET_NAME}" --address-prefix="10.0.3.0/24" --resource-group "${RESOURCE_GROUP}" --subscription ${SUBSCRIPTION}
azure network vnet subnet create --name sql-subnet --vnet-name "${VNET_NAME}" --address-prefix="10.0.4.0/24" --resource-group "${RESOURCE_GROUP}" --subscription ${SUBSCRIPTION}
azure network vnet subnet create --name mgmt-subnet --vnet-name "${VNET_NAME}" --address-prefix="10.0.5.0/24" --resource-group "${RESOURCE_GROUP}" --subscription ${SUBSCRIPTION}

# Step 4 - define the load balancer and network security rules

# Step 4.1 - Create the load balancer, public IP and frontend IP 
azure network public-ip create --name "${APP_NAME}-lb-pip" --allocation-method Static \
    --domain-name-label "${APP_NAME}" ${POSTFIX}

azure network lb create --name "${APP_NAME}-lb" ${POSTFIX}
azure network lb frontend-ip create --name "${APP_NAME}-lb-fip" \
    --lb-name "${APP_NAME}-lb" --public-ip-name "${APP_NAME}-lb-pip" \
    --resource-group ${RESOURCE_GROUP} --subscription ${SUBSCRIPTION}
    
# Step 4.2 - Create the load balancer address pool and obtain the 
# ID of the load balancer address pool (for use when creating NICs)
azure network lb address-pool create --name "${APP_NAME}-lb-address-pool" \
    --lb-name "${APP_NAME}-lb" --resource-group "${RESOURCE_GROUP}"
    
# 4.3 - Create the forwarding rule and health probe
azure network lb probe create --name "${APP_NAME}-lb-probe" --lb-name "${APP_NAME}-lb" \
    --protocol http --port 80 --path "/" --interval 15 --count 1 \
    --resource-group "${RESOURCE_GROUP}" --subscription "${SUBSCRIPTION}"

azure network lb rule create --name "${APP_NAME}-web-rule" --lb-name "${APP_NAME}-lb" --protocol tcp \
    --frontend-port 80 --backend-port 80 --frontend-ip-name "${APP_NAME}-lb-fip" \
    --backend-address-pool-name "${APP_NAME}-lb-address-pool" \
    --probe-name "${APP_NAME}-lb-probe" \
    --resource-group "${RESOURCE_GROUP}" --subscription "${SUBSCRIPTION}"

     
# Step 5 - create a diagnostics storage account
diagnostics_storage_account=${APP_NAME//-/}diag
azure storage account create --type=LRS --tags "${TAGS}" ${POSTFIX} "${diagnostics_storage_account}"

# TODO - assign roles to VMs in tags

# Step 6.1 - Create the gateway VMs and add them to the address pool for the load balancer
azure availset create --name "${APP_NAME}-gateway-as" ${POSTFIX}
for i in `seq 1 4`;
do
	create_vm "${APP_NAME}-gw${i}" "${APP_NAME}-vnet" "fe-subnet" "Windows" "${WINDOWS_BASE_IMAGE}" \
        "Standard_DS1" "${diagnostics_storage_account}" "${APP_NAME}-gateway-as"
         
    azure network nic address-pool add --name "${APP_NAME}-gw${i}-0nic" \
        --lb-address-pool-name "${APP_NAME}-lb-address-pool" --lb-name "${APP_NAME}-lb" \
        --resource-group "${RESOURCE_GROUP}" --subscription "${SUBSCRIPTION}"  
done    

# Step 6.2 - Create the ElasticSearch master and data VMs
azure availset create --name "${APP_NAME}-es-master-as" ${POSTFIX}
for i in `seq 1 3`;
do
   create_vm "${APP_NAME}-es-master${i}" "${APP_NAME}-vnet" "es-master-subnet" "Linux" "${LINUX_BASE_IMAGE}" \
        "Standard_DS1" "${diagnostics_storage_account}" "${APP_NAME}-es-master-as"
   azure vm set --name "${APP_NAME}-es-master${i}" --tags "${TAGS};role=elasticsearch-master" \
       --resource-group ${RESOURCE_GROUP} --subscription ${SUBSCRIPTION}
done
azure availset create --name "${APP_NAME}-es-data-as" ${POSTFIX}
for i in `seq 1 3`;
do
   create_vm "${APP_NAME}-es-data${i}" "${APP_NAME}-vnet" "es-data-subnet" "Linux" "${LINUX_BASE_IMAGE}" \
       "Standard_DS1" "${diagnostics_storage_account}" "${APP_NAME}-es-data-as"
   azure vm set --name "${APP_NAME}-es-data${i}" --tags "${TAGS};role=elasticsearch-data" \
       --resource-group ${RESOURCE_GROUP} --subscription ${SUBSCRIPTION}
done

# Step 6.3 - Create the SQL VMs
azure availset create --name "${APP_NAME}-sql-as" ${POSTFIX}
create_vm "${APP_NAME}-sql0" "${APP_NAME}-vnet" "sql-subnet" "Windows" "${WINDOWS_BASE_IMAGE}" \
    "Standard_DS1" "${diagnostics_storage_account}" "${APP_NAME}-sql-as"
create_vm "${APP_NAME}-sql1" "${APP_NAME}-vnet" "sql-subnet" "Windows" "${WINDOWS_BASE_IMAGE}" \
    "Standard_DS1" "${diagnostics_storage_account}" "${APP_NAME}-sql-as"

# Step 7 - Create the jump box, with a public IP address
create_vm "${APP_NAME}-jumpbox" "${APP_NAME}-vnet" "mgmt-subnet" "Windows" "${WINDOWS_BASE_IMAGE}" \
    "Standard_DS1" "${diagnostics_storage_account}" 
azure network public-ip create --name "${APP_NAME}-bastion-pip" --domain-name-label "${APP_NAME}-bastion" ${POSTFIX}
azure network nic set --name "${APP_NAME}-jumpbox-0nic" --public-ip-name "${APP_NAME}-bastion-pip" \
    --resource-group "${RESOURCE_GROUP}" --subscription "${SUBSCRIPTION}"
# TODO - set a static internal address for the bastion host
