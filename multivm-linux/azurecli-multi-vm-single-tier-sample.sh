#!/bin/bash

############################################################################
#script for generating infrastructure for 1 tier multi linux VMS of        #
# user choice. It creates azure resource group, storage accounts for VMS   #
# vnet, subnets for tiers, load balance and NSG rules                      #
# tags for main variables used                                             #
# ScriptCommandParameters                                                  #
# ScriptVars                                                               #
############################################################################

############################################################################
# User defined functions for 3tier script                                  #
# errhandle : handles errors via trap if any exception happens             # 
# in the cli execution or if the user interrupts with CTRL+C               #
# allowing for fast interruption                                           #
# CreateVM: provisions the VMS for one tier. Parameters: VM Name,Tier name #
# (web, biz, db, manage) avalability set(true or false) Load balancer name #
############################################################################

# error handling or interruption via ctrl-c.
# line number and error code of executed command is passed to errhandle function

trap 'errhandle $LINENO $?' SIGINT ERR

errhandle()
{ 
  echo "Error or Interruption at line ${1} exit code ${2} "
  exit ${2}
}

create_vm()
{
  
  echo "Creating VM ${1}"

  VM_NAME="${APP_NAME}-vm${1}"
  NIC_NAME="${VM_NAME}-nic1"
  VHD_STORAGE="${VM_NAME//-}st1"
  SSH_PORT=$((50000 + $1))
 
  #Create NIC for VM1
  
  azure network nic create --name $NIC_NAME --subnet-name $SUBNET_NAME \
  --subnet-vnet-name $VNET_NAME --location $LOCATION $POSTFIX
  #Add NIC to back-end address pool
  
  azure network nic address-pool add --name $NIC_NAME \
  --lb-name $LB_NAME --lb-address-pool-name $LB_BACKEND_NAME $POSTFIX
  
  #Create NAT rule for RDP
  azure network lb inbound-nat-rule create --name "ssh-vm${1}" \
  --frontend-port $SSH_PORT --backend-port 22 --lb-name $LB_NAME \
  --frontend-ip-name $LB_FRONTEND_NAME $POSTFIX
  
  #Add NAT rule to the NIC
  azure network nic inbound-nat-rule add --name $NIC_NAME --lb-name \
  $LB_NAME --lb-inbound-nat-rule-name "ssh-vm${1}" $POSTFIX
  
  #Create the storage account for the OS VHD
  azure storage account create --type PLRS --location $LOCATION \
  $VHD_STORAGE $POSTFIX
  
  #Create the VM
  azure vm create --name $VM_NAME --os-type Linux \
  --image-urn $LINUX_BASE_IMAGE --vm-size $VM_SIZE \
  --vnet-subnet-name $SUBNET_NAME --nic-name $NIC_NAME \
  --vnet-name $VNET_NAME --storage-account-name $VHD_STORAGE \
  --os-disk-vhd "${VM_NAME}-osdisk.vhd" --admin-username $USERNAME \
  --ssh-publickey-file $PUBLICKEYFILE --boot-diagnostics-storage-uri \
  "https://${DIAGNOSTICS_STORAGE}.blob.core.windows.net/" \
  --availset-name $AVAILSET_NAME --location $LOCATION $POSTFIX
  
  #Attach a data disk
  azure vm disk attach-new --vm-name $VM_NAME --size-in-gb 128 \
  --vhd-name "${VM_NAME}-data1.vhd" --storage-account-name $VHD_STORAGE $POSTFIX

}

###############################################################################
############################## End of user defined functions ##################
###############################################################################

if [ $# -ne 2  ]
then
	echo  "Usage:  ${0}  subscription-id public-ssh-key-file"
	exit
fi

if [ ! -f $2  ]
then
	echo "Public Key file ${2} does not exist. please generate it"
	echo "ssh-keygen -t rsa -b 2048"
	exit
fi


# Explicitly set the subscription to avoid confusion as to which subscription
# is active/default
# ScriptCommandParameters
SUBSCRIPTION=$1
PUBLICKEYFILE=$2

# ScriptVars  
LOCATION=eastus2
APP_NAME=app90
ENVIRONMENT=dev
USERNAME=testuser
NUM_VM_INSTANCES=2
RESOURCE_GROUP="${APP_NAME}-${ENVIRONMENT}-rg"
AVAILSET_NAME="${APP_NAME}-as"
LB_NAME="${APP_NAME}-lb"
LB_FRONTEND_NAME="${LB_NAME}-frontend"
LB_BACKEND_NAME="${LB_NAME}-backend-pool"
LB_PROBE_NAME="${LB_NAME}-probe"
IP_NAME="${APP_NAME}-pip"
SUBNET_NAME="${APP_NAME}-subnet"
VNET_NAME="${APP_NAME}-vnet"
DIAGNOSTICS_STORAGE="${APP_NAME//-}diag"

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

POSTFIX="--resource-group ${RESOURCE_GROUP} --subscription ${SUBSCRIPTION}"
azure config mode arm

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#Create resources

#Create the enclosing resource group
azure group create --name $RESOURCE_GROUP  --location $LOCATION --subscription $SUBSCRIPTION

#Create the availability set
azure availset create --name $AVAILSET_NAME --location $LOCATION $POSTFIX

# Create the VNet
azure network vnet create --address-prefixes 10.0.0.0/16  --name $VNET_NAME --location $LOCATION $POSTFIX

#Create the subnet
azure network vnet subnet create --vnet-name $VNET_NAME \
--address-prefix 10.0.0.0/24 --name $SUBNET_NAME $POSTFIX

#Create the public IP address (dynamic)
azure network public-ip create --name $IP_NAME --location $LOCATION $POSTFIX

#Create the storage account for diagnostics logs
azure storage account create --type LRS --location $LOCATION $POSTFIX $DIAGNOSTICS_STORAGE

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#Load balancer

#Create the load balancer
azure network lb create --name $LB_NAME --location $LOCATION $POSTFIX

#Create LB front-end and associate it with the public IP address
azure network lb frontend-ip create --name $LB_FRONTEND_NAME \
--lb-name $LB_NAME --public-ip-name $IP_NAME $POSTFIX

#Create LB back-end address pool
azure network lb address-pool create --name $LB_BACKEND_NAME --lb-name $LB_NAME $POSTFIX

#Create a health probe for an HTTP endpoint
azure network lb probe create --name $LB_PROBE_NAME \
--lb-name $LB_NAME --port 80 --interval 5 --count 2 --protocol http --path "/"  $POSTFIX

#Create a load balancer rule for HTTP
azure network lb rule create --name "${LB_NAME}-rule-http" \
--protocol tcp --lb-name $LB_NAME \
--frontend-port 80 --backend-port 80 \
--frontend-ip-name $LB_FRONTEND_NAME --probe-name $LB_PROBE_NAME $POSTFIX

########################################################################


# all machines are passed for the parameters for metrics collection
for ((i=1; i<=$NUM_VM_INSTANCES ; i++))
do 
  create_vm $i 
done






