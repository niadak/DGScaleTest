﻿param([string]$targetTFSUrl,
      [string]$patToken,
      [string]$agentDownloadUrl = 'https://go.microsoft.com/fwlink/?linkid=867184',
      [string]$existingAgentFolder = "",
      [string]$action = "PrintEffect")

$ErrorActionPreference="Stop"

# Basic input validations
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() ).IsInRole( [Security.Principal.WindowsBuiltInRole] “Administrator”)){ 
    throw "Run command in an administrator PowerShell prompt"
};

If ($PSVersionTable.PSVersion -lt (New-Object System.Version("3.0"))){
    throw "The minimum version of Windows PowerShell that is required by the script (3.0) does not match the currently running version of Windows PowerShell."
}


# Auto detect existing agent folder
if ($existingAgentFolder -eq ""){
    $ServiceNamePrefix = 'vstsagent*'
    $agentServices = Get-Service -Name $ServiceNamePrefix
    if ($agentServices.Count -eq 1){
        $serviceName = $agentServices[0].Name;
        $service = get-wmiobject -query "select * from win32_service where name = `'$serviceName`'";
        $serviceExePath = $service.pathname;
        # $serviceExePath will have value like "C:\vstsAgent2\A8\bin\AgentService.exe"
        $existingAgentFolder = $serviceExePath.Substring(1, $serviceExePath.Length - 22);
    }
}

if ($existingAgentFolder -eq ""){
    throw "Not able to auto detect existing agent folder. Provide the existingAgentFolder as input parameter.";
}

cd $existingAgentFolder;

if (-not (Test-Path '.\.agent')){
    throw "No agent installed in this path. Please run this script from Agent Home Directory. Generally it is in C:\vstsagent folder."
}


# Collect information about the existing agent
$sourceTFSUrl = "NoAbleToReadAgentFile"
$collectionName = "NoAbleToReadAgentFile"
$projectName = "NoAbleToReadAgentFile"
$deploymentGroupId = "NoAbleToReadAgentFile"
$deploymentGroupName = "NoAbleToReadAgentFile"
$agentName = "NoAbleToReadAgentFile"
$tags = "NoAbleToReadAgentFile"
$deploymentMachineId = "NoAbleToReadAgentFile"

foreach($line in Get-Content .\.agent) {
    $token = $line.split('"');

    if ($token[1] -eq 'serverUrl'){
        $sourceTFSUrl = $token[3];
        if ($sourceTFSUrl.StartsWith($targetTFSUrl)){
            Write-Verbose -Verbose "Agent is already configured to the TFS $targetTFSUrl";
            return 0;
        }
    }

    if ($token[1] -eq 'collectionName'){
        $collectionName = $token[3];
    }

    if ($token[1] -eq 'projectId'){
        $projectName = $token[3];
    }

    if ($token[1] -eq 'deploymentGroupId'){
        $deploymentGroupId = $token[2].Substring(2, $token[2].Length - 3);
    }

    if ($token[1] -eq 'agentName'){
        $agentName = $token[3];
    }
}

# Get the Deployment group name
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$patToken"))
$getDeploymentGroupUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/deploymentgroups/' + $deploymentGroupId + '?api-version=4.0-preview.1'
 
$dg = Invoke-RestMethod -Uri $getDeploymentGroupUrl -Method Get -Headers @{Authorization = "Basic $encodedPat"} -ContentType "application/json"
$deploymentGroupName = $dg.name


# Get the Machine Tags
$getDeploymentMachineUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/deploymentgroups/' + $deploymentGroupId + '/machines?name=' + $agentName + '&api-version=4.0-preview.1'

$dm = Invoke-RestMethod -Uri $getDeploymentMachineUrl -Method Get -Headers @{Authorization = "Basic $encodedPat"} -ContentType "application/json"
$tags = $dm.value[0].tags -join ",";
$deploymentMachineId = $dm.value[0].id;

if ($dm.value[0].agent.status -ne 'offline'){
    Write-Verbose -Verbose "Agent is already configured to the TFS $targetTFSUrl"
    return 0;
}


# Create and go to new agent folder
If(-NOT (Test-Path $env:SystemDrive\'vstsagent'))
{
    mkdir $env:SystemDrive\'vstsagent'
}

$newAgentFolfer = "";

cd $env:SystemDrive\'vstsagent';
for ($i=1; $i -lt 100; $i++){
    $destFolder="A"+$i.ToString();
    if (-NOT (Test-Path ($destFolder))){
        $newAgentFolfer = $destFolder;
        break;
    }
};
$newAgentPath = $env:SystemDrive + '\vstsagent\' + $newAgentFolfer;

if ($action -ne "apply"){
    Write-Verbose -Verbose "If action is set to apply, this script will delete the existing non usable offline agent $agentName from the deployment group $deploymentGroupName in the TFS $targetTFSUrl and re-configure a new agent in $newAgentPath path with same name and properties inclusing tags $tags. All the old deployment histroty will be deleted.";
    return 0;
}

Write-Verbose -Verbose "Start execution : It will delete the existing non usable offline agent $agentName from the deployment group $deploymentGroupName in the TFS $targetTFSUrl and re-configure a new agent in $newAgentPath path with same name and properties inclusing tags $tags. All the old deployment histroty will be deleted.";
mkdir $newAgentFolfer;
cd $newAgentFolfer; 

# download the agent bits.
$agentZip= $agentZip="$PWD\agent.zip";
$DefaultProxy=[System.Net.WebRequest]::DefaultWebProxy;$securityProtocol=@();
$securityProtocol+=[Net.ServicePointManager]::SecurityProtocol;
$securityProtocol+=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::SecurityProtocol=$securityProtocol;
$WebClient=New-Object Net.WebClient;
    
if($DefaultProxy -and (-not $DefaultProxy.IsBypassed($agentDownloadUrl)))
{
    $WebClient.Proxy= New-Object Net.WebProxy($DefaultProxy.GetProxy($agentDownloadUrl).OriginalString, $True);
};

$WebClient.DownloadFile($agentDownloadUrl, $agentZip);

Add-Type -AssemblyName System.IO.Compression.FileSystem;[System.IO.Compression.ZipFile]::ExtractToDirectory( $agentZip, "$PWD"); 

# Delete existing agent reference from the target TFS	
$deleteDeploymentMachineUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/deploymentgroups/' + $deploymentGroupId + '/machines/' + $deploymentMachineId + '?api-version=4.0-preview.1'
Invoke-RestMethod -Uri $deleteDeploymentMachineUrl -Method Delete -Headers @{Authorization = "Basic $encodedPat"} -ContentType "application/json"


# Re-configure the agent to the target TFS
if ($tags -ne ""){
    .\config.cmd --deploymentgroup --url $targetTFSUrl --collectionname $collectionName --projectname $projectName --deploymentgroupname $deploymentGroupName --agent $agentName --auth Integrated --runasservice --work '_work' --unattended --adddeploymentgrouptags --deploymentgrouptags $tags
}
else{
    .\config.cmd --deploymentgroup --url $targetTFSUrl --collectionname $collectionName --projectname $projectName --deploymentgroupname $deploymentGroupName --agent $agentName --auth Integrated --runasservice --work '_work' --unattended
}
