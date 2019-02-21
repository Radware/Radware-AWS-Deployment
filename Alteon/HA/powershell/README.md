# Alteon Windows Batch Deployment Script

## Table Of Contents ###
- [Description](#description )
- [How To Use](#how-to-use )
  * [Required modules](#Required-modules)
  * [Using Non-Interactive Mode](#Using-Non-Interactive-Mode)
  * [Using Interactive Mode](#Using-Interactive-Mode)

## Description ##
The following script is used to deploy two Alteon VMs on AWS (EC2) using Microsoft windows batch script (including the Alteon config).<br>
Using the interactive mode it's possible to use existing object in AWS (deployment in existing VPC, Subnet, etc...) .<br>
Using the Non-interactive mode The script will create all new infrastructure objects.<br>

## How To Use ##
### Required modules ###
In order to use the script make sure you have installed PowerShell AWS tools 
For instructions on AWS CLI please refer to https://aws.amazon.com/powershell/

### Using Non-Interactive Mode ###
the script ("AWSDep.ps1") contains mandatory adjustable parameters:
* _AwsKey - The API Key in AWS
* _AwsSec - the secret corresponding with the key.
* _region - the region we'll use for the deployment

And some more optional parameters 
* _Name       - Name for this deployment, this will be the base for all  
* _VpcPref    - The Full IP segment to use
* _DataPref    - IP segment to use for the management network
* _MgmtPref    - IP segment to use for the data network
* _realIPList - list of backend servers

### Using Interactive Mode ###
the script ("AWSDep.ps1") contains 3 adjustable parameters:
* _AwsKey - The API Key in AWS
* _AwsSec - the secret corresponding with the key.
* _region - the region we'll use for the deployment
while running, the script will request some more data
