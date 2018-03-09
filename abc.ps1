
param([string]$agentDownloadUrl)

if($agentDownloadUrl.Length -eq 0)
{
    throw 'parameter not passed properly'
}

Write-Verbose -Verbose 'Test script executed successfully. parameter passed $agentDownloadUrl'
Write-Host 'Test script executed successfully. parameter passed $agentDownloadUrl'

if($agentDownloadUrl.Length -ne 0)
{
    throw 'parameter passed properly'
}
