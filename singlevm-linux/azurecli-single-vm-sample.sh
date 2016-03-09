#!/bin/bash


if [ -z  $1  ]
then
	echo  "Usage: " $0 " subscription-id"
	exit
fi


LOCATION=eastus2
APP_NAME=app1
ENVIRONMENT=dev
USERNAME=administrator1
PASSWORD="AweS0me@PW"


# Explicitly set the subscription to avoid confusion as to which subscription
# is active/default
SUBSCRIPTION=$1



VM_NAME=$APP_NAME-vm0
#echo $VM_NAME

RESOURCE_GROUP="${APP_NAME}-${ENVIRONMENT}-rg"
VM_NAME="${APP_NAME}-vm0"
IP_NAME="${APP_NAME}-pip"
NIC_NAME="${VM_NAME}-0nic"
NSG_NAME="${APP_NAME}-nsg"
SUBNET_NAME="${APP_NAME}-subnet"
VNET_NAME="${APP_NAME}-vnet"
VHD_STORAGE="${VM_NAME//-}st0"
DIAGNOSTICS_STORAGE="${VM_NAME//-}diag"

# For UBUNTU,OPENSUSE,RHEL use the following command to get the list of URNs:
# UBUNTU
# azure vm image list $LOCATION% canonical ubuntuserver 14.04.3-LTS
# SUSE
# azure vm image $LOCATION  suse opensuse 13.2
#RHEL
#azure vm image list eastus2  redhat RHEL 7.2
 
LINUX_BASE_IMAGE=canonical:ubuntuserver:14.04.3-LTS:14.04.201601190

#For a list of VM sizes see...
VM_SIZE=Standard_DS1

# Set up the postfix variables attached to most CLI commands

POSTFIX="--resource-group ${RESOURCE_GROUP} --location ${LOCATION} --subscription ${SUBSCRIPTION}"

azure config mode arm

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#Create resources

#Create the enclosing resource group
azure group create --name $RESOURCE_GROUP  --location $LOCATION --subscription $SUBSCRIPTION

# Create the VNet
azure network vnet create --address-prefixes 172.17.0.0/16  --name $VNET_NAME $POSTFIX

#Create the network security group
azure network nsg create --name $NSG_NAME $POSTFIX

#Create the subnet
azure network vnet subnet create --vnet-name $VNET_NAME --address-prefix  172.17.0.0/24 --name $SUBNET_NAME --network-security-group-name $NSG_NAME --resource-group $RESOURCE_GROUP --subscription $SUBSCRIPTION

#Create the public IP address (dynamic)
azure network public-ip create --name $IP_NAME $POSTFIX

#Create the NIC
azure network nic create --public-ip-name $IP_NAME --subnet-name $SUBNET_NAME --subnet-vnet-name $VNET_NAME  --name $NIC_NAME $POSTFIX

#Create the storage account for the OS VHD
azure storage account create --type PLRS $POSTFIX $VHD_STORAGE

#Create the storage account for diagnostics logs
azure storage account create --type LRS $POSTFIX $DIAGNOSTICS_STORAGE

#Create the VM
azure vm create --name $VM_NAME --os-type Linux --image-urn  $LINUX_BASE_IMAGE --vm-size $VM_SIZE --vnet-subnet-name $SUBNET_NAME --vnet-name $VNET_NAME --nic-name $NIC_NAME --storage-account-name $VHD_STORAGE --os-disk-vhd "${VM_NAME}-osdisk.vhd" --admin-username $USERNAME --admin-password $PASSWORD --boot-diagnostics-storage-uri "https://${DIAGNOSTICS_STORAGE}.blob.core.windows.net/" $POSTFIX

 
#Attach a data disk
azure vm disk attach-new -s $SUBSCRIPTION -g $RESOURCE_GROUP --vm-name $VM_NAME --size-in-gb 128 --vhd-name data1.vhd --storage-account-name $VHD_STORAGE

#Allow SSH
azure network nsg rule create -s $SUBSCRIPTION -g $RESOURCE_GROUP --nsg-name $NSG_NAME --direction Inbound --protocol Tcp --destination-port-range 22  --source-port-range "*"  --priority 100 --access Allow SSHAllow

