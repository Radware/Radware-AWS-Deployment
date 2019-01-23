@echo off
:: Set Application Name
set _Name=AppName
set _VPCPref=10.0.0.0/16
set _MgmtSub=10.0.1.0/24
set _DataSub=10.0.2.0/24

:: Get ImageID
FOR /F "tokens=*" %%g IN ('aws configure get region') do (SET _Reg=%%g)
FOR /F "tokens=*" %%g IN ('aws ec2 describe-images --owners "aws-marketplace" --filters "Name=product-code,Values=bk8zsl62zq94gk739kspd36nr" "Name=ena-support,Values=true" "Name=is-public,Values=true" --region %_Reg% --query "Images[].ImageId" --output text') do (SET _AmiId=%%g)

:: Create Key Pair
FOR /F "tokens=*" %%g IN ('aws ec2 create-key-pair --key-name %_Name%Key --query "KeyMaterial" --output text') do (ECHO %%g>>key.pem)

:: Create a New VPC
FOR /F "tokens=*" %%g IN ('aws ec2 create-vpc --cidr-block %_VPCPref% --query "Vpc.VpcId" --output text') do (SET _VPC=%%g)
call aws ec2 create-tags --resource %_VPC% --tags Key=Name,Value=%_Name%VPC >> NULL

:: Create a new Internet GW and attach it to the VPC
FOR /F "tokens=*" %%g IN ('aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text') do (SET _IGW=%%g)
call aws ec2 create-tags --resource %_IGW% --tags Key=Name,Value=%_Name%IGW >> NULL
call aws ec2 attach-internet-gateway --internet-gateway-id %_IGW% --vpc-id %_VPC% >> NULL

:: Create 2 new Subnet
FOR /F "tokens=*" %%g IN ('aws ec2 create-subnet --vpc-id %_VPC% --cidr-block %_MgmtSub% --query Subnet.SubnetId --output text') do (SET _MgmtSubID=%%g)
call aws ec2 create-tags --resource %_MgmtSubID% --tags Key=Name,Value=%_Name%MGMTSub >> NULL
FOR /F "tokens=*" %%g IN ('aws ec2 create-subnet --vpc-id %_VPC% --cidr-block %_DataSub% --query Subnet.SubnetId --output text') do (SET _DataSubID=%%g)
call aws ec2 create-tags --resource %_DataSubID% --tags Key=Name,Value=%_Name%DataSub >> NULL

:: Create a new Route table with a default route pointing to the Internet GW and assign it to the new subnets
FOR /F "tokens=*" %%g IN ('aws ec2 create-route-table --vpc-id %_VPC% --query RouteTable.RouteTableId  --output text') do (SET _RtId=%%g)
call aws ec2 create-tags --resource %_RtId% --tags Key=Name,Value=%_Name%Rt >> NULL
call aws ec2 associate-route-table --route-table-id %_RtId% --subnet-id %_MgmtSubID% >> NULL
call aws ec2 associate-route-table --route-table-id %_RtId% --subnet-id %_DataSubID% >> NULL
call aws ec2 create-route --route-table-id %_RtId% --destination-cidr-block 0.0.0.0/0 --gateway-id %_IGW% >> NULL

:: Create a security group with default rules
FOR /F "tokens=*" %%g IN ('aws ec2 create-security-group --group-name %_Name%SecGr --description "Alteon Security group for %_Name%" --vpc-id %_VPC% --query GroupId --output text') do (SET _SecGr=%%g)
call aws ec2 create-tags --resource %_SecGr% --tags Key=Name,Value=%_Name%SecGr >> NULL
call aws ec2 authorize-security-group-ingress --group-id %_SecGr% --ip-permissions IpProtocol=tcp,FromPort=3121,ToPort=3121,IpRanges=[{CidrIp=%_VPCPref%}] IpProtocol=icmp,FromPort=-1,ToPort=-1,IpRanges=[{CidrIp=%_VPCPref%}] IpProtocol=udp,FromPort=2090,ToPort=2090,IpRanges=[{CidrIp=%_VPCPref%}] IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}] IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0}] >> NULL

:: Create Data Nic
FOR /F "tokens=*" %%g IN ('aws ec2 create-network-interface --subnet-id %_DataSubID% --description %_Name%Inst-Data-Nic --groups %_SecGr% --query NetworkInterface.NetworkInterfaceId  --output text') do (SET _DNic=%%g)
call aws ec2 create-tags --resource %_DNic% --tags Key=Name,Value=%_Name%InstDataNic >> NULL

:: Deploy the instance, add name TAG and attach a NIC
FOR /F "tokens=*" %%g IN ('aws ec2 run-instances --image-id %_AmiId% --count 1 --instance-type c4.large --key-name %_Name%Key --security-group-ids %_SecGr% --subnet-id %_MgmtSubID% --query Instances[].InstanceId  --output text') do (SET _InstId=%%g)

:: Allocate New Elastic IPs
FOR /F "tokens=*" %%g IN ('aws ec2 allocate-address --domain vpc --query AllocationId  --output text') do (SET _MgmtEIP=%%g)
FOR /F "tokens=*" %%g IN ('aws ec2 allocate-address --domain vpc --query AllocationId  --output text') do (SET _DataEIP=%%g)

FOR /F "tokens=*" %%g IN ('aws ec2 describe-instances --instance-ids %_InstId% --query Reservations[].Instances[].NetworkInterfaces[].NetworkInterfaceId --output text') do (SET _MNic=%%g)
call aws ec2 create-tags --resource %_MNic% --tags Key=Name,Value=%_Name%InstMgmtNic >> NULL
FOR /F "tokens=*" %%g IN ('aws ec2 describe-instances --instance-ids %_InstId% --query Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddress --output text') do (SET _MgmtPIP=%%g)
call aws ec2 create-tags --resource %_InstId% --tags Key=Name,Value=%_Name%Inst >> NULL
call aws ec2 attach-network-interface --instance-id %_InstId% --network-interface-id %_DNic% --device-index 1 >> NULL

:: ssisiate to Instance
FOR /F "tokens=*" %%g IN ('aws ec2 describe-network-interfaces --filters "Name=tag-value,Values=%_Name%InstDataNic" --query NetworkInterfaces[].PrivateIpAddress  --output text') do (SET _DataPIP=%%g)
call aws ec2 associate-address --allocation-id %_MgmtEIP% --network-interface-id %_MNic% --private-ip-address %_MgmtPIP% >> NULL
call aws ec2 associate-address --allocation-id %_DataEIP% --network-interface-id %_DNic% --private-ip-address %_DataPIP% >> NULL

FOR /F "tokens=*" %%g IN ('aws ec2 describe-addresses --allocation-ids %_MgmtEIP% --query Addresses[].PublicIp --output text') do (SET _MIP=%%g)
FOR /F "tokens=*" %%g IN ('aws ec2 describe-addresses --allocation-ids %_DataEIP% --query Addresses[].PublicIp --output text') do (SET _DIP=%%g)

ECHO "Please use ssh admin@%_MIP% to login to the new device, Note allocated Data IP is %_DIP%"
pause
