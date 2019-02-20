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
In order to use the script make sure you have installed powershell AWS tools 
For instructions on AWS CLI please refer to https://aws.amazon.com/powershell/

### Using Launch file ###
the script ("AWSDep.ps1") contains 3 adjustable parameters:
* _AwsKey - The API Key in AWS
* _AwsSec - the secret coresponding with the key.
* _region - the region we'll use for the deployment
