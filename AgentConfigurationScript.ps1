
param([string]$agentDownloadUrl,
	  [string]$vstsAccount,
	  [string]$projectName,
	  [string]$deploymentGroupName,
	  [string]$PATToken,
	  [string]$tags,
	  [int]$agentsCount = 50)

for($j=0;$j -le $agentsCount ;$j++)
{
    $ErrorActionPreference="Stop"
    
    If(-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] “Administrator”))
    { 
        throw "Run command in Administrator PowerShell Prompt"
    }
    
    If(-NOT (Test-Path $env:SystemDrive\'vstsagent'))
    {
        mkdir $env:SystemDrive\'vstsagent'
    }

    cd $env:SystemDrive\'vstsagent'
    $agentName = $env:COMPUTERNAME

    for($i=1; $i -lt 1000; $i++)
    {
        $destFolder="A"+$i.ToString();
        if(-NOT (Test-Path ($destFolder)))
        {
            $agentName = $env:COMPUTERNAME + $i
            mkdir $destFolder
            cd $destFolder
            break
        }
    }
    
    $agentZip="$PWD\agent.zip"
	  $vstsUrl = 'https://' + $vstsAccount + '.visualstudio.com/'
    
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
    
    .\config.cmd --deploymentgroup --agent $agentName --url $vstsUrl --projectname $projectName --deploymentgroupname $deploymentGroupName --auth PAT --token $PATToken --runasservice --work '_work' --unattended --adddeploymentgrouptags --deploymentgrouptags $tags

    Remove-Item $agentZip;
}
