# Alteon Windows Batch Deployment Script

## Table Of Contents ###
- [Description](#description )
- [How To Use](#how-to-use )
  * [Required modules](#Required-modules)
  * [Using Launch file](#Using-Launch-file)

## Description ##
The following script is used to deploy alteon VM on AWS using Microsoft windows batch script.<br>

## How To Use ##
### Required modules ###
In order to use the script make sure you have installed AWS CLI
For instructions on AWS CLI please refer to https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html

### Using Launch file ###
the script ("AWSDep.bat") contains 4 adjustable parameters:
* _Name - the base for the name of all resources.
  for example if _Name=AppName, the VPC will be called AppNameVPC.
* _VPCPref - the prefix will be used for VPC Creation.
* _MgmtSub - the subnet will be used for the Management subnet
* _DataSub - the subnet will be used for the Data subnet
It's possible to adjust the parameters or simply running with the default values.
