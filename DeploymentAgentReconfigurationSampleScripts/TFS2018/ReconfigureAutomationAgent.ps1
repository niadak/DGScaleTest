<# 
This is a guidance script to bring an agent queue agent online after TFS Hardware move activity for TFS2018. Post Hardware move, all the agents will be offline as the TFS server url has been updated. User can use\follow this script to bring them online. The script has to be run from Administrator PowerShell prompt on the each agent machine.

Inputs:
1. targetTFSUrl : New TFS url after hardware move.
2. patToken : PAT token from new TFS with Agent pool manage scope (at least)
3. existingAgentFolder: The script will Auto-detect the agent folder if it was running as windows service. User need to pass the folder path otherwise.
4. agentDownloadUrl: this is optional, user can specify if she wants any specific agent version to be installed.
5. agentNamePostFix : this will be appended to the new agent name to resolve the exiting agent name conflict.
6. action: By default, the script will not do any update operation, it will just print what changes will happen after the script is applied. User need to set action parameter to 'apply' to execute actual steps.

Output:
If action is set to apply, this script this script will
1. Configure a new agent to the deployment group in the TFS with same properties as the existing unusable, offline agent including tags. Name of the new agent will be appended by agentNamePostFix.
2. Old agents can be used to audit the existing request history." 
#>

param([string]$targetTFSUrl,
      [string]$patToken,
      [string]$existingAgentFolder = "",
      [string]$agentDownloadUrl = 'https://go.microsoft.com/fwlink/?linkid=867184',
      [string]$agentNamePostFix = "Reconfigured",
      [string]$action = "PrintEffect")

$ErrorActionPreference="Stop"

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
        $existingAgentFolder = $serviceExePath.Substring(1, $serviceExePath.Length - 22);
    }
}

if ($existingAgentFolder -eq ""){
    throw "Not able to auto detect existing agent folder. Provide the existingAgentFolder as input parameter.";
}

cd $existingAgentFolder;

if (-not (Test-Path '.\.agent')){
    throw "No agent installed in this path. Please run this script from Agent Home Directory."
}


# Collect information about the existing agent
$sourceTFSUrl = "NoAbleToReadAgentFile"
$poolId = "NoAbleToReadAgentFile"
$poolName = "NoAbleToReadAgentFile"
$agentName = "NoAbleToReadAgentFile"

foreach($line in Get-Content .\.agent) {
    $token = $line.split('"');

    if ($token[1] -eq 'serverUrl'){
        $sourceTFSUrl = $token[3];
        if ($sourceTFSUrl.StartsWith($targetTFSUrl)){
            Write-Verbose -Verbose "Agent is already configured to the TFS $targetTFSUrl"
            return 0;
        }
    }
	
	if ($token[1] -eq 'poolId'){
        $poolId = $token[2].Substring(2, $token[2].Length - 3);
    }

    if ($token[1] -eq 'agentName'){
        $agentName = $token[3];
    }
}

# Get the Agent pool name
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$patToken"))
$getPoolUrl = $targetTFSUrl +  '/_apis/distributedtask/pools/' + $poolId + '?api-version=4.0'
 $getPoolUrl
$pool = Invoke-RestMethod -Uri $getPoolUrl -Method Get -Headers @{Authorization = "Basic $encodedPat"} -ContentType "application/json"
$poolName = $pool.name
$poolName

$newAgentName = $agentName + $agentNamePostFix;

$newAgentName

# Validate that new agent is not already configured
$getAgentUrl = $targetTFSUrl +  '/_apis/distributedtask/pools/' + $poolId + '/agents?name=' + $newAgentName + '&api-version=4.0'
$getAgentUrl
$agent = Invoke-RestMethod -Uri $getAgentUrl -Method Get -Headers @{Authorization = "Basic $encodedPat"} -ContentType "application/json"

if ($dm.value.Length -ne 0){
    Write-Verbose -Verbose "Agent $newAgentName is already configured to the TFS $targetTFSUrl"
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
    Write-Verbose -Verbose "If action is set to apply, this script will configure an agent with name $newAgentName in $newAgentPath path to the agent pool $poolName in the TFS $targetTFSUrl with same properties as the existing unusable, offline agent $agentName. Old agents can be used to audit the existing request history.";
    return 0;
}

Write-Verbose -Verbose "Start execution : It will configure an agent with name $newAgentName in $newAgentPath path to the agent pool $poolName in the TFS $targetTFSUrl with same properties as the existing unusable, offline agent $agentName. Old agents can be used to audit the existing request history.";

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

.\config.cmd --url $targetTFSUrl --pool $poolName --agent $newAgentName --auth Integrated --runasservice --work '_work' --unattended
