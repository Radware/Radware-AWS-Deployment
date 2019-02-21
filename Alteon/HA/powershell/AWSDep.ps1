$_AwsKey='AKIAJTIJAQ4AI4UYYZ6Q'
$_AwsSec='ZtlIsG+Nlf0LLyMpXV1/lKl0SE9fTQTCDUTBuUf6'
$_Name="ValTest9"
$_VpcPref="10.0.0.0/16"
$_DataPref="10.0.0.0/24"
$_MgmtPref="10.0.1.0/24"
$_realIPList=@(
    "10.0.1.10"
    "10.0.1.11"
    "10.0.1.12"
)
Set-AWSCredential -AccessKey $_AwsKey -SecretKey $_AwsSec -StoreAs default
Initialize-AWSDefaultConfiguration -ProfileName default -Region us-west-2

$_AMI=(Get-EC2Image -Owners "aws-marketplace" -Filters @{ Name = "product-code"; Values = "bk8zsl62zq94gk739kspd36nr" } | Where-Object  -Property "Public" -eq -Value True | Where-Object  -Property "EnaSupport" -eq -Value True)

Write-Host "Will deploy"$_AMI.Name

################################
############# Tags #############
################################
$_tag=New-Object Amazon.EC2.Model.Tag
$_tag.Key="Name"

function AddTag {
    Param (
        $_obj,
        $_type 
    )
    $_tag.Value=$_Name+$_type
    New-EC2tag -Resource $_obj -Tag $_tag 
}

function CreateSubnet {
    Param (
        $_subpref
    )
    New-EC2Subnet -VpcId $_Vpc -CidrBlock $_subpref
}

function FindRR {
    param (
        $rrtbl,
        $subid
    )
    foreach ($element in $rrtbl) {
        foreach ($assoc in $element.Associations ) {
            if ($assoc.SubnetId -eq $subid) {
                return $element
            } elseif ( $assoc.Main ) { $return=$element }
        }
    }
    return $return
}

function MngRules {
    param (
        $SecID
    )
    $Rule = new-object Amazon.EC2.Model.IpPermission 
    $Rule.IpProtocol = "tcp"
    $Rule.FromPort = "443"
    $Rule.ToPort = "443"
    $Rule.IpRanges.Add( "0.0.0.0/0" ) 
    Grant-EC2SecurityGroupIngress -GroupId $SecID -IpPermissions @( $Rule )
    $Rule = new-object Amazon.EC2.Model.IpPermission 
    $Rule.IpProtocol = "tcp"
    $Rule.FromPort = "2222"
    $Rule.ToPort = "2222"
    $Rule.IpRanges.Add( "0.0.0.0/0" ) 
    Grant-EC2SecurityGroupIngress -GroupId $SecID -IpPermissions @( $Rule )
}

function DataRules {
    param (
        $SecID,
        $sub
    )
    $Rule = new-object Amazon.EC2.Model.IpPermission 
    $Rule.IpProtocol = "tcp"
    $Rule.FromPort = "443"
    $Rule.ToPort = "443"
    $Rule.IpRanges.Add( "0.0.0.0/0" ) 
    Grant-EC2SecurityGroupIngress -GroupId $SecID -IpPermissions @( $Rule )
    $Rule = new-object Amazon.EC2.Model.IpPermission 
    $Rule.IpProtocol = "tcp"
    $Rule.FromPort = "3121"
    $Rule.ToPort = "3121"
    $Rule.IpRanges.Add( $sub ) 
    Grant-EC2SecurityGroupIngress -GroupId $SecID -IpPermissions @( $Rule )
    $Rule = new-object Amazon.EC2.Model.IpPermission 
    $Rule.IpProtocol = "udp"
    $Rule.FromPort = "2090"
    $Rule.ToPort = "2090"
    $Rule.IpRanges.Add( $sub ) 
    Grant-EC2SecurityGroupIngress -GroupId $SecID -IpPermissions @( $Rule )
    $Rule = new-object Amazon.EC2.Model.IpPermission 
    $Rule.IpProtocol = "icmp"
    $Rule.FromPort = "1"
    $Rule.ToPort = "1"
    $Rule.IpRanges.Add( $sub ) 
    Grant-EC2SecurityGroupIngress -GroupId $SecID -IpPermissions @( $Rule )
}

$_maskList=@('0.0.0.0','128.0.0.0','192.0.0.0','224.0.0.0','240.0.0.0','248.0.0.0','252.0.0.0','254.0.0.0','255.0.0.0','255.128.0.0','255.192.0.0','255.224.0.0','255.240.0.0','255.248.0.0','255.252.0.0','255.254.0.0','255.255.0.0','255.255.128.0','255.255.192.0','255.255.224.0','255.255.240.0','255.255.248.0','255.255.252.0','255.255.254.0','255.255.255.0','255.255.255.128','255.255.255.192','255.255.255.224','255.255.255.240','255.255.255.248','255.255.255.252','255.255.255.254','255.255.255.255')

################################
############# Key Pair #########
################################
$_keypair = New-EC2KeyPair -KeyName $_Name'Key' 

 
################################
############# VPC ##############
################################
$_Vpc=(New-EC2Vpc -CidrBlock "$_VpcPref").vpcid
AddTag $_Vpc "Vpc" 

################################
########### Subnet  ############
################################
$_MgmtSub = CreateSubnet $_MgmtPref
AddTag $_MgmtSub.SubnetId "MgmtSubnet"
$_DataSub = CreateSubnet $_DataPref
AddTag $_DataSub.SubnetId "DataSubnet"

################################
###### Internet Gateway ########
################################
$_TMP1=Get-EC2RouteTable | Where-Object -Property "VpcId" -eq -Value $_Vpc
$_TMP=New-EC2InternetGateway
Add-EC2InternetGateway -InternetGatewayId $_TMP.InternetGatewayId -VpcId $_Vpc
AddTag $_TMP.InternetGatewayId 'IntGw'
$_TMP2=FindRR $_TMP1 $_MgmtSub.SubnetId
$_TMP3=FindRR $_TMP1 $_DataSub.SubnetId
New-EC2Route -RouteTableId $_TMP2.RouteTableId -DestinationCidrBlock 0.0.0.0/0 -GatewayId $_TMP.InternetgatewayID
if ($_TMP3 -ne $_TMP2) { New-EC2Route -RouteTableId $_TMP3.RouteTableId -DestinationCidrBlock 0.0.0.0/0 -GatewayId $_TMP.InternetgatewayID }

################################
############ NICs ##############
################################
$_DNic1=New-EC2NetworkInterface -SubnetId $_DataSub.SubnetId -Description $_Name"Instance Data Network interface" -SecondaryPrivateIpAddressCount 1
AddTag $_DNic1.NetworkInterfaceId 'InstDataNic'
$Data1Pub = New-EC2Address -Domain vpc
AddTag $Data1Pub.AllocationId 'DataIP'
$_Data1Priv=($_DNic1.PrivateIpAddresses | Where-Object -Property "Primary" -ne -value True).PrivateIpAddress
Register-EC2Address -PrivateIpAddress $_Data1Priv -AllocationId $Data1Pub.AllocationId -NetworkInterfaceId $_DNic1.NetworkInterfaceId

$_DNic2=New-EC2NetworkInterface -SubnetId $_DataSub.SubnetId -Description $_Name"Instance Data Network interface" -SecondaryPrivateIpAddressCount 1
AddTag $_DNic2.NetworkInterfaceId 'InstDataNic'
$_Data2Priv=($_DNic2.PrivateIpAddresses | Where-Object -Property "Primary" -ne -value True).PrivateIpAddress

$_MNic1=New-EC2NetworkInterface -SubnetId $_MgmtSub.SubnetId -Description $_Name" Instance Management Network interface"
AddTag $_MNic1.NetworkInterfaceId 'InstMgmtNic'
$Mgmt1Pub = New-EC2Address -Domain vpc
AddTag $Mgmt1Pub.AllocationId 'MgmtIP'
Register-EC2Address -PrivateIpAddress $_MNic1.PrivateIpAddress -AllocationId $Mgmt1Pub.AllocationId -NetworkInterfaceId $_MNic1.NetworkInterfaceId

$_MNic2=New-EC2NetworkInterface -SubnetId $_MgmtSub.SubnetId -Description $_Name" Instance Management Network interface"
AddTag $_MNic2.NetworkInterfaceId 'InstMgmtNic'
$Mgmt2Pub = New-EC2Address -Domain vpc
AddTag $Mgmt2Pub.AllocationId 'MgmtIP'
Register-EC2Address -PrivateIpAddress $_MNic2.PrivateIpAddress -AllocationId $Mgmt2Pub.AllocationId -NetworkInterfaceId $_MNic2.NetworkInterfaceId


################################
####### Security Group #########
################################
$_TMP=New-EC2SecurityGroup -GroupName $_Name'MngSecGrp' -GroupDescription 'Security Group for the Management network of $_Name' -VpcId $_Vpc
AddTag $_TMP 'MngSecGrp'
MngRules $_TMP
Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_MNic1.NetworkInterfaceId -Group $_TMP
Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_MNic2.NetworkInterfaceId -Group $_TMP

$_TMP=New-EC2SecurityGroup -GroupName $_Name'DataSecGrp' -GroupDescription 'Security Group for the Data network of $_Name' -VpcId $_Vpc
AddTag $_TMP 'DataSecGrp'
DataRules $_TMP $_DataSub.CidrBlock
Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_DNic1.NetworkInterfaceId -Group $_TMP
Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_DNic2.NetworkInterfaceId -Group $_TMP

################################
########## Instance ############
################################
$_Inst1 = New-EC2Instance -ImageId $_AMI.ImageId -KeyName $_keypair.KeyName -InstanceType c4.large -NetworkInterface @( (New-Object Amazon.EC2.Model.InstanceNetworkInterfaceSpecification -property @{"NetworkInterfaceId"=$_MNic1.NetworkInterfaceId; "DeviceIndex"="0"}), (New-Object Amazon.EC2.Model.InstanceNetworkInterfaceSpecification -property @{"NetworkInterfaceId"=$_DNic1.NetworkInterfaceId; "DeviceIndex"="1"})) 
AddTag $_inst1.Instances[0].InstanceId 'Inst1'

$_Inst2 = New-EC2Instance -ImageId $_AMI.ImageId -KeyName $_keypair.KeyName -InstanceType c4.large -NetworkInterface @( (New-Object Amazon.EC2.Model.InstanceNetworkInterfaceSpecification -property @{"NetworkInterfaceId"=$_MNic2.NetworkInterfaceId; "DeviceIndex"="0"}), (New-Object Amazon.EC2.Model.InstanceNetworkInterfaceSpecification -property @{"NetworkInterfaceId"=$_DNic2.NetworkInterfaceId; "DeviceIndex"="1"})) 
AddTag $_inst2.Instances[0].InstanceId 'Inst2'

#####################################################
########## Prepare Authentication header ############
#####################################################

## Disable certificate validation
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
Remove-Variable response -ErrorAction SilentlyContinue
$credential1 = New-Object System.Management.Automation.PSCredential( "admin", (ConvertTo-SecureString -String ($_Inst1.Instances[0].InstanceId) -AsPlainText -Force) )
$credential2 = New-Object System.Management.Automation.PSCredential( "admin", (ConvertTo-SecureString -String ($_Inst2.Instances[0].InstanceId) -AsPlainText -Force) )
$counter=0
Write-Host -NoNewline "Waiting for Alteon to load..."
do {
    Start-Sleep -s 5
    Write-Host -NoNewline "."
    $counter++
    try{$response=Invoke-WebRequest ('https://'+$Mgmt1Pub.PublicIp+'/config') -Method PUT -Body ( ( @{ sysName=$_Name+"_1" } ) | ConvertTo-Json ) -Credential $credential1 -UseBasicParsing }catch{$response=@()}
    Write-Host -NoNewline "."
} until ( $counter -ge 300 -or $response.StatusCode -eq 200 ) 
if (-not $response.StatusCode -eq 200) {
    Write-Host "Alteon Didn't Respond! Please try manually"
    Write-Host 'WBM Access = https://'+($MgmtPub.PublicIp)+'/'
    return 
}
try{$response=Invoke-WebRequest ('https://'+$Mgmt1Pub.PublicIp+'/config') -Method PUT -Body ( ( @{ sysName=$_Name+"_2" } ) | ConvertTo-Json ) -Credential $credential2 -UseBasicParsing }catch{$response=@()}
if (-not $response.StatusCode -eq 200) {
        do {
        Start-Sleep -s 5
        Write-Host -NoNewline "."
        $counter++
        try{$response=Invoke-WebRequest ('https://'+$Mgmt2Pub.PublicIp+'/config') -Method PUT -Body ( ( @{ sysName=$_Name+"_2" } ) | ConvertTo-Json ) -Credential $credential2 -UseBasicParsing }catch{$response=@()}
        Write-Host -NoNewline "."
    } until ( $counter -ge 300 -or $response.StatusCode -eq 200 ) 
    if (-not $response.StatusCode -eq 200) {
        Write-Host "Alteon Didn't Respond! Please try manually"
        Write-Host 'WBM Access = https://'+($MgmtPub.PublicIp)+'/'
        return 
    }
}

## AWS Creds
$json = ( @{ agAwsNewCfgAccessId=$_AwsKey; agAwsNewCfgSecretAccessKey=$_AwsSec } ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt1Pub.PublicIp+'/config')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential1 -UseBasicParsing 
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt2Pub.PublicIp+'/config')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential2 -UseBasicParsing 

## AWS VIP IP
$json = ( @{ Index='1'; PrivateIp=$_Data1Priv; PeerIp=$_Data2Priv; FloatingIp=$DataPub.PublicIp } ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt1Pub.PublicIp+'/config/AgAwsNewCfgAssociatedIpTable/1/')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential1 -UseBasicParsing 
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt2Pub.PublicIp+'/config/AgAwsNewCfgAssociatedIpTable/1/')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential2 -UseBasicParsing 

## Set HA Mode 
$json = ( @{ haNewCfgMode="3" } ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt1Pub.PublicIp+'/config')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential1 -UseBasicParsing 
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt2Pub.PublicIp+'/config')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential2 -UseBasicParsing 

## Add IF to HA
$json = ( @{ haSwitchNewCfgAddIf="1" } ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt1Pub.PublicIp+'/config')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential1 -UseBasicParsing 
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt2Pub.PublicIp+'/config')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential2 -UseBasicParsing 

## Create L3 interface
$json = ( @{State="2"; Index="1"; Description="Data Nic"; Addr=$_DNic1.PrivateIpAddress; Mask=$_maskList[$_DataSub.CidrBlock.Split('/')[1]]; Vlan="1"; BootpRelay="1"; Peer=$_DNic2.PrivateIpAddress } ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt1Pub.PublicIp+'/config/IpNewCfgIntfTable/1/')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential1 -UseBasicParsing 
$json = ( @{State="2"; Index="1"; Description="Data Nic"; Addr=$_DNic2.PrivateIpAddress; Mask=$_maskList[$_DataSub.CidrBlock.Split('/')[1]]; Vlan="1"; BootpRelay="1"; Peer=$_DNic1.PrivateIpAddress } ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt2Pub.PublicIp+'/config/IpNewCfgIntfTable/1/')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential2 -UseBasicParsing 

## Create Reals
$_counter=0
foreach ($_realIP in $_realIPList) {
    $_counter++
    $json = ( @{ State="2"; Index=$_counter; IpAddr=$_realIP } ) | ConvertTo-Json
    $response = Invoke-RestMethod -Uri ('https://'+$Mgmt1Pub.PublicIp+'/config/SlbNewCfgEnhRealServerTable/'+$_counter+'/')  -Method POST -Body $json -ContentType 'application/json' -Credential $credential1 -UseBasicParsing 
    $response = Invoke-RestMethod -Uri ('https://'+$Mgmt2Pub.PublicIp+'/config/SlbNewCfgEnhRealServerTable/'+$_counter+'/')  -Method POST -Body $json -ContentType 'application/json' -Credential $credential2 -UseBasicParsing 

    $json = ( @{ Index="1"; AddServer=$_counter } ) | ConvertTo-Json
    $response = Invoke-RestMethod -Uri ('https://'+$Mgmt1Pub.PublicIp+'/config/SlbNewCfgEnhGroupTable/1/')  -Method PUT -Body $json -ContentType 'application/json' -Credential $credential1 -UseBasicParsing 
    $response = Invoke-RestMethod -Uri ('https://'+$Mgmt2Pub.PublicIp+'/config/SlbNewCfgEnhGroupTable/1/')  -Method PUT -Body $json -ContentType 'application/json' -Credential $credential2 -UseBasicParsing 
}

## Create VIRT
$json = ( @{ VirtServerState="2"; VirtServerIndex="1"; VirtServerIpVer="1"; VirtServerIpAddress=$_Data1Priv; VirtServerVname="VIP 1" } ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt1Pub.PublicIp+'/config/SlbNewCfgEnhVirtServerTable/1/')  -Method POST -Body $json -ContentType 'application/json' -Credential $credential1 -UseBasicParsing  
$json = ( @{ VirtServerState="2"; VirtServerIndex="1"; VirtServerIpVer="1"; VirtServerIpAddress=$_Data2Priv; VirtServerVname="VIP 1" } ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt2Pub.PublicIp+'/config/SlbNewCfgEnhVirtServerTable/1/')  -Method POST -Body $json -ContentType 'application/json' -Credential $credential2 -UseBasicParsing  

## Create Service 
$json = ( @{ ServIndex="1"; VirtPort="80"; Index="1"} ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt1Pub.PublicIp+'/config/SlbNewCfgEnhVirtServicesTable/1/1/')  -Method POST -Body $json -ContentType 'application/json' -Credential $credential1 -UseBasicParsing 
$response = Invoke-RestMethod -Uri ('https://'+$Mgmt2Pub.PublicIp+'/config/SlbNewCfgEnhVirtServicesTable/1/1/')  -Method POST -Body $json -ContentType 'application/json' -Credential $credential2 -UseBasicParsing 

## Apply Config
$response = Invoke-WebRequest -Uri ("https://"+$Mgmt1Pub.PublicIp+"/config?action=apply")  -Method POST -ContentType 'application/json'  -Body ""  -Credential $credential1 -UseBasicParsing 
$response = Invoke-WebRequest -Uri ("https://"+$Mgmt2Pub.PublicIp+"/config?action=apply")  -Method POST -ContentType 'application/json'  -Body ""  -Credential $credential2 -UseBasicParsing 

Write-Host "Deployment was complete!"
Write-Host -NoNewline "Please use the following IP for management of device 1:"
Write-Host $Mgmt1Pub.PublicIp
Write-Host -NoNewline "The following IP for management of device 2:"
Write-Host $Mgmt2Pub.PublicIp
write-Host -NoNewline "And the following IP for Data:"
Write-Host -NoNewline $DataPub.PublicIp
