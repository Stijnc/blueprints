#!/bin/bash

#define functions

create_vm()
{ 
  
  TIER_NAME=$2  
  SUBNET_NAME=$3
  HAS_LB=$4
  LB_NAME=$5
  
  VM_NAME="${$APP_NAME}-${TIER_NAME}-vm${1}"
  NIC_NAME="${VM_NAME}-0nic"
  VHD_STORAGE="${VM_NAME//-}st0"
  RDP_PORT=((50001 + $1))
  LB_FRONTEND_NAME="${LB_NAME}-frontend"
  LB_BACKEND_NAME="${LB_NAME}-backend-pool"
  
  #Create NIC for VM1
  azure network nic create --name $NIC_NAME --subnet-name $SUBNET_NAME --subnet-vnet-name $VNET_NAME --location $LOCATION $POSTFIX
  
  if [ $HAS_LB ]
  then
	#Add NIC to back-end address pool
	azure network nic address-pool add --name $NIC_NAME --lb-name $LB_NAME --lb-address-pool-name $LB_BACKEND_NAME $POSTFIX
  fi
  
  #Create the storage account for the OS VHD
  azure storage account create --type PLRS --location $LOCATION \
  $VHD_STORAGE $POSTFIX
  
  #Create the VM
  azure vm create --name $VM_NAME --os-type Linux \
  --image-urn $LINUX_BASE_IMAGE --vm-size $VM_SIZE --vnet-subnet-name $SUBNET_NAME \
  --nic-name $NIC_NAME --vnet-name $VNET_NAME --storage-account-name $VHD_STORAGE \
  --os-disk-vhd "${VM_NAME%}-osdisk.vhd" --admin-username $USERNAME --admin-password $PASSWORD \
  --boot-diagnostics-storage-uri "https://${DIAGNOSTICS_STORAGE}.blob.core.windows.net/" \
  --availset-name $AVAILSET_TIER_NAME --location $LOCATION $POSTFIX

  #Attach a data disk
  azure vm disk attach-new --vm-name $VM_NAME --size-in-gb 128 \
    --vhd-name "${VM_NAME}-data1.vhd" --storage-account-name $VHD_STORAGE $POSTFIX
  
  
}

CreateTier()
{
  
  echo Creating %1 tier
  TIER_NAME=$1
  NUM_VM_INSTANCES=$2
  ADDRESS_PREFIX=$3
  LB_NEEDED=$4
  SUBNET_NAME="${APP_NAME}-${TIER_NAME}tier-subnet"
  AVAILSET_TIER_NAME="${APP_NAME}-${TIER_NAME}tier-as"
  LB_NAME="${APP_NAME}-${TIER_NAME}tier-lb"
  LB_FRONTEND_NAME="${LB_NAME}-frontend"
  LB_BACKEND_NAME="${LB_NAME}-backend-pool"
  LB_PROBE_NAME="${LB_NAME}-probe"
  # Create the subnet
  azure network vnet subnet create --vnet-name $VNET_NAME --address-prefix $ADDRESS_PREFIX --name $SUBNET_NAME $POSTFIX
  
  if [ $LB_NEEDED  ] then
  
  
    #Create the load balancer
    azure network lb create --name $LB_NAME --location $LOCATION $POSTFIX
    if [ $TIER_NAME = 'web' ] 
    then
      
      echo Creating frontend-ip for web tier lb
      #Associate the frontend-ip with the public IP address
      azure network lb frontend-ip create --name $LB_FRONTEND_NAME --lb-name $LB_NAME --public-ip-name $PUBLIC_IP_NAME $POSTFIX
    
  fi
      
    if [ $TIER_NAME = 'biz' ] 
    then
 
      echo Creating frontend-ip for biz tier using subnet $SUBNET_NAME
      #Associate the frontend-ip with a private IP address
      azure network lb frontend-ip create --name $LB_FRONTEND_NAME --lb-name $LB_NAME \
	--private-ip-address 10.0.1.5 --subnet-name $SUBNET_NAME% --subnet-vnet-name $VNET_NAME $POSTFIX
      
    fi
    
    #Create LB back-end address pool
    azure network lb address-pool create --name $LB_BACKEND_NAME --lb-name $LB_NAME $POSTFIX
    #Create a health probe for an HTTP endpoint
    
    azure network lb probe create --name $LB_PROBE_NAME --lb-name $LB_NAME --port 80 --interval 5 --count 2 --protocol http --path "/"  $POSTFIX
    
    #Create a load balancer rule for HTTP
    azure network lb rule create --name "${LB_NAME}-rule-http" --protocol tcp \
      --lb-name $LB_NAME --frontend-port 80 --backend-port 80 \
      --frontend-ip-name $LB_FRONTEND_NAME --probe-name $LB_PROBE_NAME $POSTFIX
 
  fi

  #Create the availability sets
  
  azure availset create --name $AVAILSET_TIER_NAME --location $LOCATION $POSTFIX
  

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#Create VMs and per-VM resources
  for ((i=0; i<$NUM_VM_INSTANCES ; i++))
  do 
   VM_NAME="${APP_NAME}-vm${i}"
   #params VM_NAME NIC_NAME VHD_STORAGE SSH_PORT NAT_RULE
   create_vm  $VM_NAME "${VM_NAME}-0nic" "${VM_NAME//-}st0" $((5001+i)) "ssh-vm${i}"   
  done

}


if [ -z  $1  ] | [ -z  $2  ]
then
	echo  "Usage:  ${0}  subscription-id admin-address-prefix"
	exit
	
fi


# Set up variables to build out the naming conventions for deploying
# the cluster

LOCATION=eastus2
APP_NAME=app1
ENVIRONMENT=dev
USERNAME=testuser
PASSWORD="AweS0me@PW"

NUM_VM_INSTANCES_WEB_TIER=3
NUM_VM_INSTANCES_BIZ_TIER=3
NUM_VM_INSTANCES_DB_TIER=2
NUM_VM_INSTANCES_MANAGE_TIER=1

SSH_ACCESS_PORT=22

#Explicitly set the subscription to avoid confusion as to which subscription
#is active/default

SUBSCRIPTION=$1

ADMIN_ADDRESS_PREFIX=$2

#Set up the names of things using recommended conventions
RESOURCE_GROUP="${APP_NAME}-${ENVIRONMENT}-rg"
VNET_NAME="${APP_NAME}-vnet"
PUBLIC_IP_NAME="${APP_NAME}-pip"
BASTION_PUBLIC_IP_NAME="${APP_NAME}-bastion-pip"
DIAGNOSTICS_STORAGE="${APP_NAME//-}diag"
JUMP_BOX_NIC_NAME="${APP_NAME}-manage-vm1-0nic"


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

#Set up the postfix variables attached to most CLI commands
POSTFIX="--resource-group ${RESOURCE_GROUP} --subscription ${SUBSCRIPTION}"

azure config mode arm
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#Create resources


#Create the enclosing resource group
azure group create --name $RESOURCE_GROUP --location $LOCATION --subscription $SUBSCRIPTION

#Create the VNet
azure network vnet create --address-prefixes 10.0.0.0/16 --name $VNET_NAME --location $LOCATION $POSTFIX

#Create the storage account for diagnostics logs
azure storage account create --type LRS --location $LOCATION $POSTFIX $DIAGNOSTICS_STORAGE

#Create the public IP address (dynamic)
azure network public-ip create --name $PUBLIC_IP_NAME --location $LOCATION $POSTFIX

#Create the management public IP address (dynamic)
azure network public-ip create --name $BASTION_PUBLIC_IP_NAME --location $LOCATION


