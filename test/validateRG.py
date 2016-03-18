#!/usr/bin/python

# Backlog
# TODO: Add final dictionary comparision 
# TODO: Genrate report


import argparse
import json
from pprint import pprint

# Handle input
parser = argparse.ArgumentParser()
parser.add_argument("TargetRG_JSON", help="The deployed resource group JSON file")
parser.add_argument("DesiredState_JSON", help="The desired state definition JSON file used for validation")

args = parser.parse_args()
print(args)
print(args.TargetRG_JSON)
print(args.DesiredState_JSON)



# Retrieve JSON
with open(args.TargetRG_JSON) as data_file: 
	targetRGJSON = json.load(data_file)
	
with open(args.DesiredState_JSON) as data_file:    
    dsRGJSON = json.load(data_file)	
	
# Input an Array
# Each array entry is a Dict.

def parseJson(data):
	tmpDict = {}
	print("parseJson")
	print("len data",len(data))
	for i in data:
		print("i[type]:",i['type'])
		if (i['type'] in tmpDict):
			print("updating entry")
			tmpDict[i['type']] = tmpDict[i['type']] + 1
			print("tmpDict[",i['type'],"]=",tmpDict[i['type']] )
		else:
			print("adding entry",i['type'])
			tmpDict[i['type']] = 1
			print("tmpDict[",i['type'],"]=",tmpDict[i['type']] )
		print("\n ")
		# for k, v in i.items():
			# print(k,v)
	print("end parseJson tmpDIct",tmpDict)
	return tmpDict
	
	

			
print("TargetRG JSON PRINT")
#pprint(targetRGJSON)
tgDict = parseJson(targetRGJSON["resources"])
print("\ntgDict:",tgDict)


print("\n\nDesired State JSON Print")
# #pprint(dsRGJSON)
dsDict = parseJson(dsRGJSON["resources"])
print ("\ndsDict:",dsDict)

