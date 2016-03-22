#!/usr/bin/python

# Backlog
# Review


import argparse
import json
from pprint import pprint

# Handle input
parser = argparse.ArgumentParser()
parser.add_argument("TargetRG_JSON", help="The deployed resource group JSON file")
parser.add_argument("DesiredState_JSON", help="The desired state definition JSON file used for validation")

args = parser.parse_args()
print("\nRunning Validate Resource Group against desired state.")


# Retrieve JSON
with open(args.TargetRG_JSON) as data_file: 
	targetRGJSON = json.load(data_file)
	
with open(args.DesiredState_JSON) as data_file:    
    dsRGJSON = json.load(data_file)	
	
# Input an Array
# Each array entry is a Dict.

def is_number(s):
	try:
		float(s)
		return True
	except ValueError:
		return False

# Go through JSON Dictionary and return a Dictionary with a count for each deployed asset.
def getAssetCount(data):
	tmpDict = {}
	for i in data:
		#print("i[type]:",i['type'])
		if (i['type'] in tmpDict):
			#print("updating entry")
			tmpDict[i['type']] = tmpDict[i['type']] + 1
			#print("tmpDict[",i['type'],"]=",tmpDict[i['type']] )
		else:
			#print("adding entry",i['type'])
			tmpDict[i['type']] = 1
			#print("tmpDict[",i['type'],"]=",tmpDict[i['type']] )
		#print("\n ")
	return tmpDict
	
	
# Compare the deployed assets of the targeted deployement with the desired state.
def compareAssets(refDict, tarDict):
	tmpDict = {}
	keysRef = refDict.keys()
	keysTar = tarDict.keys()
	for x in keysRef:
		if (x in tarDict):
			if(refDict[x] != tarDict[x]):
				tmpDict[x]= refDict[x] - tarDict[x]
		else:
			tmpDict[x] = "is missing!"
			
	for y in keysTar:
		if (y not in refDict):
			tmpDict[y] = "asset is not present in desired state!"
	return tmpDict
	
# Generate a report of the findings
def generateReport(reportDict, refDict):
	if (len(reportDict) > 0):
		print("Failed: Deployments do not match:")
		for k,v  in reportDict.items():
			#print ("type:reportDict:",type(reportDict[k]))
			if (is_number(reportDict[k])):
				if (v > 0):
					print("\t",k,"is missing",v,"deployments.")
				else: 
					print("\t",k,"has",abs(v),"extra deployments.")
			else:
				print("\t",k,v)
	else:
		print("Passed: Deployment matches desired state!")
		for k,v in refDict.items():
			print("\t",k,"has",v,"deployed")
		

# parse through JSON to count assets	
tgDict = getAssetCount(targetRGJSON["resources"])
dsDict = getAssetCount(dsRGJSON["resources"])

tmpDict = compareAssets(dsDict,tgDict)
print("\n",'-'*10,"Results",'-'*10)
generateReport(tmpDict,dsDict)
