param([string]$agentDownloadUrl = 'https://github.com/Microsoft/vsts-agent/releases/download/v2.129.1/vsts-agent-win-x64-2.129.1.zip',
	  [string]$vstsAccount = 'testking123',
	  [string]$projectName = 'AzureProj',
	  [string]$deploymentGroupName = 'DeploymentGroupScaleTest-automated',
	  [string]$PATToken = 'jdlfj',
	  [string]$tags = 'Web',
	  [int]$agentsCount = 2)

$ErrorActionPreference="Stop"
    
If(-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] “Administrator”))
{ 
    throw "Run command in Administrator PowerShell Prompt"
}
    
If(-NOT (Test-Path $env:SystemDrive\'vstsagent'))
{
    mkdir $env:SystemDrive\'vstsagent'
}
	
for($i=1; $i -le $agentsCount; $i++)
{
    cd $env:SystemDrive\'vstsagent'
    $agentName = $env:COMPUTERNAME

    for($j=$i; $j -lt 1000; $j++)
    {
        $destFolder="A"+$j.ToString();
        if(-NOT (Test-Path ($destFolder)))
        {
            $agentName = $env:COMPUTERNAME + $j
            mkdir $destFolder
            cd $destFolder
            break
        }
    }
    
    $agentZip= $env:SystemDrive + '\vstsagent\agent.zip'
    $vstsUrl = 'https://' + $vstsAccount + '.visualstudio.com/'

    if($i -eq 1)
    {
        # we need to download latest agent in first iteration
        if(Test-Path $agentZip)
        {
            Remove-Item $agentZip;
        }
		
        $DefaultProxy=[System.Net.WebRequest]::DefaultWebProxy;$securityProtocol=@();
        $securityProtocol+=[Net.ServicePointManager]::SecurityProtocol;
        $securityProtocol+=[Net.SecurityProtocolType]::Tls12;[Net.ServicePointManager]::SecurityProtocol=$securityProtocol;
        $WebClient=New-Object Net.WebClient;
    
        if($DefaultProxy -and (-not $DefaultProxy.IsBypassed($agentDownloadUrl)))
        {
            $WebClient.Proxy= New-Object Net.WebProxy($DefaultProxy.GetProxy($agentDownloadUrl).OriginalString, $True);
        };

        $WebClient.DownloadFile($agentDownloadUrl, $agentZip);
    }
	
    Add-Type -AssemblyName System.IO.Compression.FileSystem;[System.IO.Compression.ZipFile]::ExtractToDirectory( $agentZip, "$PWD");    
    
    .\config.cmd --deploymentgroup --agent $agentName --url $vstsUrl --projectname $projectName --deploymentgroupname $deploymentGroupName --auth PAT --token $PATToken --runasservice --work '_work' --unattended --adddeploymentgrouptags --deploymentgrouptags $tags
}
