$_AwsKey=''
$_AwsSec=''
$_region='us-west-2'
Set-AWSCredential -AccessKey $_AwsKey -SecretKey $_AwsSec -StoreAs default
Initialize-AWSDefaultConfiguration -ProfileName default -Region $_region

Write-Host "================================="
Write-Host "Welcome to AWS Deployment script!"
Write-Host "All resource names will be ProjectName+ResourceAcrenem"
Write-Host 'For example: if the name is AlteonAWS the Key Pair name will be "AlteonAWSKey"'
$_Name=Read-Host -Prompt 'Please provide a name for the project'

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
    $tag.Value=$_name+$_type
    New-EC2tag -Resource $_obj -Tag $tag 
    Remove-Variable ans -ErrorAction SilentlyContinue
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
    $response = Invoke-WebRequest -Uri ("https://"+$MgmtPub.PublicIp+"/config?action=apply")  -Method POST -ContentType 'application/json'  -Body "" -Headers $Headers 
}
################################
############# Key Pair #########
################################
Write-Host "=============== Key Pairs =================="
$_KeyList=Get-EC2KeyPair| select -ExpandProperty KeyName

Write-Host "Currently available key pairs are:"
$menu = @{}
for ($i=1;$i -le $_KeyList.count; $i++) { 
    Write-Host "$i. $($_KeyList[$i-1])" 
    $menu.Add($i,($_KeyList[$i-1]))
}
Write-Host "N. To create a new Key"
Remove-Variable ans -ErrorAction SilentlyContinue
do { $ans = Read-Host 'Please make a selection' } until ( ($ans -in 0..$_KeyList.count) -or $ans -eq 'N' -or $ans -eq 'n') 
if ($ans -eq 'N' -or $ans -eq 'n') { 
    $_keypair = New-EC2KeyPair -KeyName $_Name'Key' 
} else {
    $_keypair=$menu.Item([int]$ans)
}


 
################################
############# VPC ##############
################################
Write-Host "=============== VPC =================="
$_VpcTable=@{}
$_VpcList=@()
foreach ($element in Get-EC2Vpc) {
	foreach ($tag in $element.Tag) {
        if($tag.Key -eq "Name") { 
            $_VpcList+=$tag.value
            $_VpcTable+=@{$tag.value=$element.VpcId}
        }
    }
}
$menu = @{}
for ($i=1;$i -le $_VPCList.count; $i++) { 
    Write-Host "$i. $($_VPCList[$i-1])" 
    $menu.Add($i,($_VpcTable[$_VPCList[$i-1]]))
}
Write-Host "N. To create a new VPC"
Remove-Variable ans -ErrorAction SilentlyContinue
do { $ans = Read-Host 'Please make a selection' } until ( ($ans -in 0..$_VPCList.count) -or $ans -eq 'N' -or $ans -eq 'n') 
if ($ans -eq 'N' -or $ans -eq 'n') { 
    $_VpcPref=Read-Host 'Please provide a Prefix for the VPC (Default is 10.0.0.0/16)' 
    if ($_VpcPref -eq "") { $_VpcPref="10.0.0.0/16" }
    $_Vpc=(New-EC2Vpc -CidrBlock "$_VpcPref").vpcid
    AddTag $_Vpc "Vpc" 
} else {
    $_Vpc=$menu.Item([int]$ans)
}

################################
########### Subnet  ############
################################
$_TMP=Get-EC2Subnet | Where-Object -Property "VpcId" -eq -Value $_Vpc
$_SubTable=@{}
$_SubList=@()
foreach ($element in $_TMP) {
    $_SubTable+=@{$element.CidrBlock=$element.SubnetId}
    foreach ($tag in $element.Tag) {
        if($tag.Key -eq "Name") {
            $_TMPBool=1
            $_SubList+=$element.CidrBlock+' ('+$tag.value+')'
        }
    }
    if ( !$_TMPBool ) {
        $_SubList+=$element.CidrBlock+' ( No-Name )'
    }
    $_TMPBool=0
}
if ( @($_TMP).Count -eq "0" ) {
    $_TMPStr=Read-Host "Please provide ip prefix for the Management Subnet (Default is 10.0.0.0/24)"
    if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.0.0/24" }
    $_MgmtSub = CreateSubnet $_TMPStr
    AddTag $_MgmtSub.SubnetId "MgmtSubnet"

    $_TMPStr=Read-Host "Please provide ip prefix for the Data Subnet (Default is 10.0.1.0/24)"
    if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.1.0/24" }
    $_DataSub = CreateSubnet $_TMPStr
    AddTag $_DataSub.SubnetId "DataSubnet"
} elseif (  @($_TMP).Count -eq "1" ) {
    Write-Host "=============== Subnets =================="
    Write-Host "1: Press '1' To Create New Subnets for both Management and Data"
    Write-Host "2: Press '2' To Create New Subnet for the Management but use an existing one for Data."
    Write-Host "3: Press '3' To Create Use the existing Subnet for Management subnet but Create a new one for Data."
    $input = Read-Host "Please make a selection"
    switch ($input) {
        '1' { 
            $_TMPStr=Read-Host "Please provide ip prefix for the Management Subnet (Default is 10.0.0.0/24)"
            if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.0.0/24" }
            $_MgmtSub = CreateSubnet $_TMPStr
            AddTag $_MgmtSub.SubnetId "MgmtSubnet"

            $_TMPStr=Read-Host "Please provide ip prefix for the Data Subnet (Default is 10.0.0.0/24)"
            if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.1.0/24" }
            $_DataSub = CreateSubnet $_TMPStr
            AddTag $_DataSub.SubnetId "DataSubnet"
                
        } '2' { 
            $_TMPStr=Read-Host "Please provide ip prefix for the Management Subnet (Default is 10.0.0.0/24)"
            if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.0.0/24" }
            $_MgmtSub = CreateSubnet $_TMPStr
            AddTag $_MgmtSub.SubnetId "MgmtSubnet"

            $menu = @{}
            for ($i=1;$i -le $_SubList.count; $i++) { 
                Write-Host "$i. $($_SubList[$i-1])" 
                $menu.Add($i,($_SubTable[$_SubList[$i-1].Split()[0]]))
            }

            [int]$ans = Read-Host 'Enter selection'
            $_DataSub=$_TMP | Where-Object -Property "SubnetId" -eq -Value $menu.Item($ans)
        } '3' { 
            $menu = @{}
            for ($i=1;$i -le $_SubList.count; $i++) { 
                Write-Host "$i. $($_SubList[$i-1])" 
                $menu.Add($i,($_SubTable[$_SubList[$i-1].Split()[0]]))
            }
            [int]$ans = Read-Host 'Enter selection'
            $_MgmtSub=$_TMP | Where-Object -Property "SubnetId" -eq -Value $menu.Item($ans)

            $_TMPStr=Read-Host "Please provide ip prefix for the Management Subnet (Default is 10.0.0.0/24)"
            if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.0.0/24" }
            $_DataSub = CreateSubnet $_TMPStr
            AddTag $_DataSub.SubnetId "MgmtSubnet"
        }
    }
} else {
    Write-Host "=============== VPC =================="
    Write-Host "1: Press '1' To Create New Subnets for both Management and Data"
    Write-Host "2: Press '2' To Create New Subnet for the Management but use an existing one for Data."
    Write-Host "3: Press '3' To Use an existing Subnet for Management subnet but Create a new one for Data."
    Write-Host "4: Press '4' To Use existing Subnets for both Management and Data"
    $input = Read-Host "Please make a selection"
     switch ($input) {
        '1' { 
            $_TMPStr=Read-Host "Please provide ip prefix for the Management Subnet (Default is 10.0.0.0/24)"
            if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.0.0/24" }
            $_MgmtSub = CreateSubnet $_TMPStr
            AddTag $_MgmtSub.SubnetId "MgmtSubnet"

            $_TMPStr=Read-Host "Please provide ip prefix for the Data Subnet (Default is 10.0.0.0/24)"
            if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.1.0/24" }
            $_DataSub = CreateSubnet $_TMPStr
            AddTag $_DataSub.SubnetId "DataSubnet"
                
        } '2' { 
            $_TMPStr=Read-Host "Please provide ip prefix for the Management Subnet (Default is 10.0.0.0/24)"
            if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.0.0/24" }
            $_MgmtSub = CreateSubnet $_TMPStr
            AddTag $_MgmtSub.SubnetId "MgmtSubnet"

            $menu = @{}
            for ($i=1;$i -le $_SubList.count; $i++) { 
                Write-Host "$i. $($_SubList[$i-1])" 
                $menu.Add($i,($_SubTable[$_SubList[$i-1].Split()[0]]))
            }

            [int]$ans = Read-Host 'Enter selection'
            $_DataSub=$_TMP | Where-Object -Property "SubnetId" -eq -Value $menu.Item($ans)
        } '3' { 
            $menu = @{}
            for ($i=1;$i -le $_SubList.count; $i++) { 
                Write-Host "$i. $($_SubList[$i-1])" 
                $menu.Add($i,($_SubTable[$_SubList[$i-1].Split()[0]]))
            }
            [int]$ans = Read-Host 'Enter selection'
            $_MgmtSub=$_TMP | Where-Object -Property "SubnetId" -eq -Value $menu.Item($ans)

            $_TMPStr=Read-Host "Please provide ip prefix for the Management Subnet (Default is 10.0.0.0/24)"
            if ( $_TMPStr -eq "" ) { $_TMPStr="10.0.0.0/24" }
            $_DataSub = CreateSubnet $_TMPStr
            AddTag $_DataSub.SubnetId "MgmtSubnet"
        } '4' {
            $menu = @{}
            for ($i=1;$i -le $_SubList.count; $i++) { 
                Write-Host "$i. $($_SubList[$i-1])" 
                $menu.Add($i,($_SubTable[$_SubList[$i-1].Split()[0]]))
            }
            [int]$ans = Read-Host 'Enter selection'
            $_MgmtSub=$_TMP | Where-Object -Property "SubnetId" -eq -Value $menu.Item($ans)

            $menu = @{}
            for ($i=1;$i -le $_SubList.count; $i++) { 
                Write-Host "$i. $($_SubList[$i-1])" 
                $menu.Add($i,($_SubTable[$_SubList[$i-1].Split()[0]]))
            }

            [int]$ans = Read-Host 'Enter selection'
            $_DataSub=$_TMP | Where-Object -Property "SubnetId" -eq -Value $menu.Item($ans)
        }
    }
} 



################################
###### Internet Gateway ########
################################
$_TMP1=Get-EC2RouteTable | Where-Object -Property "VpcId" -eq -Value $_Vpc
if ( (FindDefRR $_TMP1 $_MgmtSub.SubnetId) -and (FindDefRR $_TMP1 $_DataSub.SubnetId)) { Write-Host "Selected Subnets already have Default route" }
else {
    $_IgwList=@()
    foreach ($element in (Get-EC2InternetGateway)) {
        foreach ($tag in $element.Tag) {
            if($tag.Key -eq "Name") {
                $_TMPBool=1
                $_TMPStr=$tag.value
            }
        }
        foreach ($attach in $element.Attachments) {
            if ($attach.VpcId -eq $_Vpc) {
                if ($_TMPBool) { 
                    $_TMPBool=0
                    $_IgwList+= $element.InternetGatewayId+' ('+$_TMPStr+')'
                } else { $_IgwList+= $element.InternetGatewayId+' ( No-Name )' }
            }
        }
    }

    if ( $_IgwList.Count -eq 0 ) {

        Write-Host "=============== Routes =================="
        Write-Host "1: Press '1' To Skip This Step"
        Write-Host "2: Press '2' To Create A New Internet Gateway and Attach it to the Subnets"
        $input = Read-Host "Please make a selection"
        switch ($input) {
            '2' { 
                $_TMP=New-EC2InternetGateway
                Add-EC2InternetGateway -InternetGatewayId $_TMP.InternetGatewayId -VpcId $_Vpc
                AddTag $_TMP.InternetGatewayId 'IntGw'
            
                $_TMP2=FindRR $_TMP1 $_MgmtSub.SubnetId
                $_TMP3=FindRR $_TMP1 $_DataSub.SubnetId
                
                New-EC2Route -RouteTableId $_TMP2.RouteTableId -DestinationCidrBlock 0.0.0.0/0 -GatewayId $_TMP.InternetgatewayID
                if ($_TMP3 -ne $_TMP2) { New-EC2Route -RouteTableId $_TMP3.RouteTableId -DestinationCidrBlock 0.0.0.0/0 -GatewayId $_TMP.InternetgatewayID }
            } 
        }
    } else {
        Write-Host "=============== Routes =================="
        Write-Host "1: Press '1' To Skip This Step"
        Write-Host "2: Press '2' To Create A New Internet Gateway and Attach it to the Subnets"
        Write-Host "3: Press '3' To Use An Existing Internet Gateway and Attach it to the Subnets"
        $input = Read-Host "Please make a selection"
        switch ($input) {
            '2' { 
                $_TMP=New-EC2InternetGateway
                Add-EC2InternetGateway -InternetGatewayId $_TMP.InternetGatewayId -VpcId $_Vpc
                AddTag $_TMP.InternetGatewayId "IntGw"
            
                $_TMP2=FindRR $_TMP1 $_MgmtSub.SubnetId
                $_TMP3=FindRR $_TMP1 $_DataSub.SubnetId
                
                New-EC2Route -RouteTableId $_TMP2.RouteTableId -DestinationCidrBlock 0.0.0.0/0 -GatewayId $_TMP.InternetgatewayID
                if ($_TMP3 -ne $_TMP2) { New-EC2Route -RouteTableId $_TMP3.RouteTableId -DestinationCidrBlock 0.0.0.0/0 -GatewayId $_TMP.InternetgatewayID }
            } '3' { 
                $menu = @{}
                for ($i=1;$i -le $_IgwList.count; $i++) { 
                    Write-Host "$i. $($_IgwList[$i-1])" 
                    $menu.Add($i,($_IgwList[$i-1].Split()[0]))
                }

                [int]$ans = Read-Host 'Enter selection'
                $_IgwId= $menu.Item($ans)

                $_TMP2=FindRR $_TMP1 $_MgmtSub.SubnetId
                $_TMP3=FindRR $_TMP1 $_DataSub.SubnetId
                
                New-EC2Route -RouteTableId $_TMP2.RouteTableId -DestinationCidrBlock 0.0.0.0/0 -GatewayId $_IgwId.InternetgatewayID
                if ($_TMP3 -ne $_TMP2) { New-EC2Route -RouteTableId $_TMP3.RouteTableId -DestinationCidrBlock 0.0.0.0/0 -GatewayId $_IgwId.InternetgatewayID }
            }
        }
    }
}

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
$_TMP=Get-EC2SecurityGroup | Where-Object -Property "VpcId" -eq -Value $_Vpc
$_secgrpTbl=@{}
$_secgrpLst=@()
foreach ($grp in $_TMP) {
    $_secgrpLst+=$grp.GroupName
    $_secgrpTbl+=@{$grp.GroupName=$grp.GroupId}
}
Write-Host "=============== Sec Groups =================="
Write-Host "1: Press '1' To Skip This Step"
Write-Host "2: Press '2' To Create a New Security Groups and assign it to the according subnets"
Write-Host "3: Press '3' To Add all rules to one existing security groups"
Write-Host "4: Press '4' To Add all rules to two seprate existing security groups"
$input = Read-Host "Please make a selection"
switch ($input) {
    '2' { 
        $_TMP=New-EC2SecurityGroup -GroupName $_Name'MngSecGrp' -GroupDescription 'Security Group for the Management network of $_Name' -VpcId $_Vpc
        AddTag $_TMP 'MngSecGrp'
        MngRules $_TMP
        Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_MNic.NetworkInterfaceId -Group $_TMP

        $_TMP=New-EC2SecurityGroup -GroupName $_Name'DataSecGrp' -GroupDescription 'Security Group for the Data network of $_Name' -VpcId $_Vpc
        AddTag $_TMP 'DataSecGrp'
        DataRules $_TMP $_DataSub.CidrBlock
        Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_DNic.NetworkInterfaceId -Group $_TMP
    } '3' {
        $menu = @{}
        for ($i=1;$i -le $_secgrpTbl.count; $i++) { 
            Write-Host "$i. $($_secgrpLst[$i-1])" 
            $menu.Add($i,($_secgrpTbl[$_secgrpLst[$i-1]]))
        }
        [int]$ans = Read-Host 'Enter selection'
        MngRules $menu.Item($ans)
        Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_MNic.NetworkInterfaceId -Group $menu.Item($ans)
        DataRules $menu.Item($ans) $_DataSub.CidrBlock
        Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_DNic.NetworkInterfaceId -Group $menu.Item($ans)
    } '4' {
        $menu = @{}
        for ($i=1;$i -le $_secgrpTbl.count; $i++) { 
            Write-Host "$i. $($_secgrpLst[$i-1])" 
            $menu.Add($i,($_secgrpTbl[$_secgrpLst[$i-1]]))
        }
        [int]$ans = Read-Host 'Please select Security Group for Management'
        MngRules $menu.Item($ans)
        Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_MNic.NetworkInterfaceId -Group $menu.Item($ans)
        $menu = @{}
        for ($i=1;$i -le $_secgrpTbl.count; $i++) { 
            Write-Host "$i. $($_secgrpLst[$i-1])" 
            $menu.Add($i,($_secgrpTbl[$_secgrpLst[$i-1]]))
        }
        [int]$ans = Read-Host 'Please select Security Group for Data'
        DataRules $menu.Item($ans) $_DataSub.CidrBlock
        Edit-EC2NetworkInterfaceAttribute -NetworkInterfaceId $_DNic.NetworkInterfaceId -Group $menu.Item($ans)
    }

}

################################
########## Instance ############
################################
$_Inst = New-EC2Instance -ImageId $_AMI.ImageId -KeyName $_keypair.KeyName -InstanceType c4.large -NetworkInterface @( (New-Object Amazon.EC2.Model.InstanceNetworkInterfaceSpecification -property @{"NetworkInterfaceId"=$_MNic.NetworkInterfaceId; "DeviceIndex"="0"}), (New-Object Amazon.EC2.Model.InstanceNetworkInterfaceSpecification -property @{"NetworkInterfaceId"=$_DNic.NetworkInterfaceId; "DeviceIndex"="1"})) 
AddTag $_inst.Instances[0].InstanceId 'Inst'

#####################################################
########## Prepare Authentication header ############
#####################################################
#$encodedCreds = 'Basic '+[System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('admin:'+))
#$Headers = @{ 
#    Authorization = $encodedCreds
#}

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
    try{$response=Invoke-WebRequest ('https://'+$MgmtPub.PublicIp+'/config') -Method PUT -Body ( ( @{ sysName=$_Name+"_1" } ) | ConvertTo-Json ) -Credential $credential -UseBasicParsing -TimeoutSec 1}catch{$response=@()}
    Write-Host -NoNewline "."
} until ( $counter -ge 300 -or $response.StatusCode -eq 200 ) 
if (-not $response.StatusCode -eq 200) {
    Write-Host "Alteon Didn't Respond! Please try manually"
    Write-Host 'WBM Access = https://'+($MgmtPub.PublicIp)+'/'
    return 
}

do {
    Write-Host "=============== Alteon Configuration =================="
    Write-Host "Press 'Q' To Skip This Step"
    Write-Host "1: Press '1' To Provide Alteon with AWS credentials"
    Write-Host "2: Press '2' To Prepare for VIP HA"
    Write-Host "3: Press '3' To Cofigure Layer 3 Interface"
    Write-Host "4: Press '4' To configure backend servers"
    Write-Host "5: Press '5' Configure Virt"
    
    $input = Read-Host "Please make a selection"
} until ( $input -eq 'q' -or $input -eq 'Q')
switch ($input) {
    '1' { 
        $json = ( @{ agAwsNewCfgAccessId=$_AwsKey; agAwsNewCfgSecretAccessKey=$_AwsSec } ) | ConvertTo-Json
        $response = Invoke-RestMethod -Uri ('https://'+$MgmtPub.PublicIp+'/config')  -Method Put -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
        if ($response.status -eq 200) { funcApply }
    } '2' {
        #$json = ( @{ Index='1'; PrivateIp=$_DataPriv; PeerIp="1.1.1.2"; FloatingIp=$DataPub.PublicIp } ) | ConvertTo-Json
        #$_URI='https://'+$MgmtPub.PublicIp+'/config/AgAwsNewCfgAssociatedIpTable/1/'
        #$response = Invoke-RestMethod -Uri $_URI  -Method Put -Body $json -ContentType 'application/json' -Headers $Headers 
    } '3' {
        $json = ( @{
            State="2"; Index="1"; Description="Data Nic"; Addr=$_DNic.PrivateIpAddress
            Mask=$_maskList[$_DataSub.CidrBlock.Split('/')[1]]; Vlan="1"; BootpRelay="1" 
        } ) | ConvertTo-Json
        $_URI='https://'+$MgmtPub.PublicIp+'/config/IpNewCfgIntfTable/1/'
        $response = Invoke-RestMethod -Uri $_URI  -Method Put -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
        if ($response.status -eq 200) { funcApply }
    } '4' {  
        $_counter=0
        do {
            do { $_realIP= Read-Host "Please input IP of backend server" } until ( validIP $_realIP -or $_realIP -eq 'Q') 
            $_counter++
            $json = ( @{ State="2"; Index=$_counter; IpAddr=$_realIP } ) | ConvertTo-Json
            $_URI='https://'+$MgmtPub.PublicIp+'/config/SlbNewCfgEnhRealServerTable/'+$_counter+'/'
            $response = Invoke-RestMethod -Uri $_URI  -Method POST -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
            if ($response.status -eq 200) { 
                Write-Host "Server Created, Adding to group..."
                funcApply 
            }
            $json = ( @{ Index="1"; AddServer=$_counter } ) | ConvertTo-Json
            $_URI='https://'+$MgmtPub.PublicIp+'/config/SlbNewCfgEnhGroupTable/1/'
            $response = Invoke-RestMethod -Uri $_URI  -Method PUT -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
            if ($response.status -eq 200) { 
                Write-Host "Server added, applying configuration"
                funcApply 
            }
            $in= Read-Host "Real was configured! Click any key for another one or 'Q' to stop"
        } until ( $in -eq 'q' -or $in -eq 'Q' )
    } '5' {
        $json = ( @{ VirtServerState="2"; VirtServerIndex="1"; VirtServerIpVer="1"; VirtServerIpAddress=$_DataPriv; VirtServerVname="VIP 1" } ) | ConvertTo-Json
        $_URI='https://'+$MgmtPub.PublicIp+'/config/SlbNewCfgEnhVirtServerTable/1/'
        $response = Invoke-RestMethod -Uri $_URI  -Method POST -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing  

        $json = ( @{ ServIndex="1"; VirtPort="80"; Index="1"} ) | ConvertTo-Json
        $_URI='https://'+$MgmtPub.PublicIp+'/config/SlbNewCfgEnhVirtServicesTable/1/1/'
        $response = Invoke-RestMethod -Uri $_URI  -Method POST -Body $json -ContentType 'application/json' -Credential $credential -UseBasicParsing 
        if ($response.status -eq 200) { funcApply }
    }
}
