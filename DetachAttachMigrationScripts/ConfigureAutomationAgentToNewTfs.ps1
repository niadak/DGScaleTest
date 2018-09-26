﻿<# 
This script is applicable for TFS 2018 or later.
This is a guidance script to configure agent queue agents to the target TFS after detach\attach activity. The script is applicable if
 1. Both source and target TFS is accessibile and
 2. The agent queues has been migrated successfully to the target TFS.

Inputs:
1. targetTFSUrl : New TFS instance url.
2. sourceTFSPatToken : PAT token from source TFS with Deployment group manage scope (at least)
3. existingAgentFolder: The script will Auto-detect the agent folder if it was running as windows service. User need to pass the folder path otherwise.
4. agentDownloadUrl: this is optional, user can specify if she wants any specific agent version to be installed.
5. action: By default, the script will not do any update operation, it will just print what changes will happen after the script is applied. User need to set action parameter to 'apply' to update execute actual steps.

Output:
If action is set to apply, this script this script will
1. Configure a new agent to the agent queue in the target TFS with same properties as the existing agent in the source TFS including tags.

Example usage:
.\ConfigureAutomationAgentToNewTfs.ps1 -targetTFSUrl <newTfsUrl> -patToken <PAT-for-old-TFS>
.\ConfigureAutomationAgentToNewTfs.ps1 -targetTFSUrl <newTfsUrl> -patToken <PAT-for-old-TFS> -existingAgentFolder <AgentFoilder (C:\vstsagents\A1)>
.\ConfigureAutomationAgentToNewTfs.ps1 -targetTFSUrl <newTfsUrl> -patToken <PAT-for-old-TFS> -existingAgentFolder <AgentFoilder (C:\vstsagents\A1)> -action 'apply'
#>

param([string]$targetTFSUrl,
      [string]$sourceTFSPatToken,
      [string]$existingAgentFolder = "",
      [string]$agentDownloadUrl = 'https://vstsagentpackage.azureedge.net/agent/2.131.0/vsts-agent-win-x64-2.131.0.zip',
      [string]$action = "PrintEffect")

$ErrorActionPreference="Stop"
$apiVersion = '5.0-preview.1'

# Basic validations
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
        $existingAgentFolder = Split-Path (Split-Path $serviceExePath -Parent) -Parent;
    }
}

if ($existingAgentFolder -eq ""){
    throw "Not able to auto detect existing agent folder. Provide the existingAgentFolder as input parameter. You can find it in agent capabilities UI as Agent.HomeDirectory.  Generally it is in C:\vstsagent folder.";
}

cd $existingAgentFolder;

if (-not (Test-Path '.\.agent')){
    throw "No agent installed in this path. Please run this script from Agent Home Directory. Generally it is in C:\vstsagent folder."
}


# Collect information about the existing agent
$sourceTFSUrl = "NoAbleToReadAgentFile"
$poolId = "NoAbleToReadAgentFile"
$poolName = "NoAbleToReadAgentFile"
$agentName = "NoAbleToReadAgentFile"

$agentproperties = Get-Content .\.agent |ConvertFrom-Json
$sourceTFSUrl = $agentproperties.serverUrl;
$poolId = $agentproperties.poolId;
$agentName = $agentproperties.agentName;

if ($sourceTFSUrl.StartsWith($targetTFSUrl)){
    Write-Verbose -Verbose "Agent $agentName is already configured to the TFS $targetTFSUrl";
    return 0;
}

# Get the Agent pool name
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$sourceTFSPatToken"))
$getPoolUrl = $sourceTFSUrl +  '/_apis/distributedtask/pools/' + $poolId + '?api-version=4.0'
 $getPoolUrl
$pool = Invoke-RestMethod -Uri $getPoolUrl -Method Get -Headers @{Authorization = "Basic $encodedPat"} -ContentType "application/json"
$poolName = $pool.name


# Create and go to new agent folder
$parentPath = Split-Path $existingAgentFolder -Parent
cd $parentPath
$newAgentFolfer = "";

for ($i=1; $i -lt 100; $i++){
    $destFolder="A"+$i.ToString();
    if (-NOT (Test-Path ($destFolder))){
        $newAgentFolfer = $destFolder;
        break;
    }
};

$newAgentPath = $parentPath + $newAgentFolfer;

if ($action -ne "apply"){
    Write-Verbose -Verbose "If action is set to apply, this script will configure an agent with name $agentName in $newAgentPath path to the agent pool $poolName in the TFS $targetTFSUrl with same properties as the existing agent $agentName in the source TFS $sourceTFSUrl.";
    return 0;
}

Write-Verbose -Verbose "Start execution : It will configure an agent with name $agentName in $newAgentPath path to the agent pool $poolName in the TFS $targetTFSUrl with same properties as the existing agent $agentName in the source TFS $sourceTFSUrl.";
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
	

# configure the agent
.\config.cmd --url $targetTFSUrl --pool $poolName --agent $agentName --auth Integrated --runasservice --work '_work' --unattended

