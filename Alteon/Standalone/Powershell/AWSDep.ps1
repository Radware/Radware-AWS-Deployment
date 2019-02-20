$_AwsKey='AKIAJYIYZ5L6QQHU7THA'
$_AwsSec='CYuTApl+kiG5CdNY7CjVNyrATt7C+XNcjqzbkU2m'
$_Name="ValTest8"
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

function FindDefRR {
    param (
        $rrtbl,
        $subid
    )
    foreach ($element in $rrtbl) {
        foreach ($assoc in $element.Associations ) {
            if ($assoc.SubnetId -eq $subid -or $assoc.Main) {
                if ($element.Routes | Where-Object -Property "DestinationCidrBlock" -eq -Value "0.0.0.0/0") {
                    $return=1
                }
            }
        }
    }
    if ($return) { return 1 }
    else { return 0 }
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

function validIP {
    param (
        $IP
    )
    $ret=1
    for ($i=0;$i -le 3; $i++) { 
        if ($IP.Split('.')[$i] -notin 0..255) {
            $ret=0
        }
    }
    if ($IP.Split('.').count -ne 4) {
        $ret=0
    }
    return $ret
}

function funcApply {
    $response = Invoke-WebRequest -Uri ("https://"+$MgmtPub.PublicIp+"/config?action=apply")  -Method POST -ContentType 'application/json'  -Body ""  -Credential $credential -UseBasicParsing 
}
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
$_DNic=New-EC2NetworkInterface -SubnetId $_DataSub.SubnetId -Description $_Name"Instance Data Network interface" -SecondaryPrivateIpAddressCount 1
AddTag $_DNic.NetworkInterfaceId 'InstDataNic'
$DataPub = New-EC2Address -Domain vpc
AddTag $DataPub.AllocationId 'DataIP'
$_DataPriv=($_DNIC.PrivateIpAddresses | Where-Object -Property "Primary" -ne -value True).PrivateIpAddress
Register-EC2Address -PrivateIpAddress $_DataPriv -AllocationId $DataPub.AllocationId -NetworkInterfaceId $_DNic.NetworkInterfaceId

$_MNic=New-EC2NetworkInterface -SubnetId $_MgmtSub.SubnetId -Description $_Name" Instance Management Network interface"
AddTag $_MNic.NetworkInterfaceId 'InstMgmtNic'
$MgmtPub = New-EC2Address -Domain vpc
AddTag $MgmtPub.AllocationId 'MgmtIP'
Register-EC2Address -PrivateIpAddress $_MNic.PrivateIpAddress -AllocationId $MgmtPub.AllocationId -NetworkInterfaceId $_MNic.NetworkInterfaceId


################################
####### Security Group #########
################################
$_TMP=New-EC2SecurityGroup -GroupName $_Name'MngSecGrp' -GroupDescription 'Security Group for the Management network of $_Name' -VpcId $_Vpc
AddTag $_TMP 'MngSecGrp'
MngRules $_TMP
Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_MNic.NetworkInterfaceId -Group $_TMP

$_TMP=New-EC2SecurityGroup -GroupName $_Name'DataSecGrp' -GroupDescription 'Security Group for the Data network of $_Name' -VpcId $_Vpc
AddTag $_TMP 'DataSecGrp'
DataRules $_TMP $_DataSub.CidrBlock
Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_DNic.NetworkInterfaceId -Group $_TMP

################################
########## Instance ############
################################
$_Inst = New-EC2Instance -ImageId $_AMI.ImageId -KeyName $_keypair.KeyName -InstanceType c4.large -NetworkInterface @( (New-Object Amazon.EC2.Model.InstanceNetworkInterfaceSpecification -property @{"NetworkInterfaceId"=$_MNic.NetworkInterfaceId; "DeviceIndex"="0"}), (New-Object Amazon.EC2.Model.InstanceNetworkInterfaceSpecification -property @{"NetworkInterfaceId"=$_DNic.NetworkInterfaceId; "DeviceIndex"="1"})) 
AddTag $_inst.Instances[0].InstanceId 'Inst'

#####################################################
########## Prepare Authentication header ############
#####################################################

## Disable certificate validation
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
Remove-Variable response -ErrorAction SilentlyContinue
$credential = New-Object System.Management.Automation.PSCredential( "admin", (ConvertTo-SecureString -String ($_Inst.Instances[0].InstanceId) -AsPlainText -Force) )
$counter=0
Write-Host -NoNewline "Waiting for Alteon to load..."
do {
    Start-Sleep -s 5
    Write-Host -NoNewline "."
    $counter++
    try{$response=Invoke-WebRequest ('https://'+$MgmtPub.PublicIp+'/config') -Method PUT -Body ( ( @{ sysName=$_Name+"_1" } ) | ConvertTo-Json ) -Credential $credential -UseBasicParsing }catch{$response=@()}
    Write-Host -NoNewline "."
} until ( $counter -ge 300 -or $response.StatusCode -eq 200 ) 
if (-not $response.StatusCode -eq 200) {
    Write-Host "Alteon Didn't Respond! Please try manually"
    Write-Host 'WBM Access = https://'+($MgmtPub.PublicIp)+'/'
    return 
}

$json = ( @{ agAwsNewCfgAccessId=$_AwsKey; agAwsNewCfgSecretAccessKey=$_AwsSec } ) | ConvertTo-Json
$response = Invoke-RestMethod -Uri ('https://'+$MgmtPub.PublicIp+'/config')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
if ($response.status -eq 200) { funcApply }

$json = ( @{State="2"; Index="1"; Description="Data Nic"; Addr=$_DNic.PrivateIpAddress; Mask=$_maskList[$_DataSub.CidrBlock.Split('/')[1]]; Vlan="1"; BootpRelay="1" } ) | ConvertTo-Json
$_URI='https://'+$MgmtPub.PublicIp+'/config/IpNewCfgIntfTable/1/'
$response = Invoke-RestMethod -Uri $_URI  -Method Put -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
if ($response.status -eq 200) { funcApply }

$_counter=0
foreach ($_realIP in $_realIPList) {
    $_counter++
    $json = ( @{ State="2"; Index=$_counter; IpAddr=$_realIP } ) | ConvertTo-Json
    $_URI='https://'+$MgmtPub.PublicIp+'/config/SlbNewCfgEnhRealServerTable/'+$_counter+'/'
    $response = Invoke-RestMethod -Uri $_URI  -Method POST -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
    if ($response.status -eq 200) { funcApply }
    $json = ( @{ Index="1"; AddServer=$_counter } ) | ConvertTo-Json
    $_URI='https://'+$MgmtPub.PublicIp+'/config/SlbNewCfgEnhGroupTable/1/'
    $response = Invoke-RestMethod -Uri $_URI  -Method PUT -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
    if ($response.status -eq 200) { funcApply }
}

$json = ( @{ VirtServerState="2"; VirtServerIndex="1"; VirtServerIpVer="1"; VirtServerIpAddress=$_DataPriv; VirtServerVname="VIP 1" } ) | ConvertTo-Json
$_URI='https://'+$MgmtPub.PublicIp+'/config/SlbNewCfgEnhVirtServerTable/1/'
$response = Invoke-RestMethod -Uri $_URI  -Method POST -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing  

$json = ( @{ ServIndex="1"; VirtPort="80"; Index="1"} ) | ConvertTo-Json
$_URI='https://'+$MgmtPub.PublicIp+'/config/SlbNewCfgEnhVirtServicesTable/1/1/'
$response = Invoke-RestMethod -Uri $_URI  -Method POST -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
if ($response.status -eq 200) { funcApply }
funcApply
