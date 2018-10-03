<# 
This script is applicable for TFS 2018 or later.
This is a guidance script to update Build defifinitions to the target TFS with new agent queues after detach\attach activity. The script is applicable if both source and target TFS are accessibile and agent queues are migrated to the target TFS

Inputs:
1. sourceTFSUrl : Source (Old) TFS instance url.
2. sourceTFSPatToken : PAT token from source TFS
3. targetTFSUrl : Target (New) TFS instance url.
4. targetTFSPatToken : PAT token from target TFS
5. collectionName: Name of the attached collection.
#>

param([string]$sourceTFSUrl,
      [string]$sourceTFSPatToken,
      [string]$targetTFSUrl,
      [string]$targetTFSPatToken,
      [string]$collectionName)

$ErrorActionPreference="Stop"
$apiVersion = '5.0-preview'

# Basic validations
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() ).IsInRole( [Security.Principal.WindowsBuiltInRole] “Administrator”)){ 
   # throw "Run command in an administrator PowerShell prompt"
};

If ($PSVersionTable.PSVersion -lt (New-Object System.Version("3.0"))){
    throw "The minimum version of Windows PowerShell that is required by the script (3.0) does not match the currently running version of Windows PowerShell."
}

$encodedSourcePat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$sourceTFSPatToken"))
$encodedTargetPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$targetTFSPatToken"))

# Get all projects in the collection
$getProjectsUrl = $sourceTFSUrl + '/' + $collectionName + '/_apis/projects/?api-version=' + $apiVersion
$projects = Invoke-RestMethod -Uri $getProjectsUrl -Method Get -Headers @{Authorization = "Basic $encodedSourcePat"} -ContentType "application/json"
for($i=0; $i -lt $projects.count; $i++ )
{
    $projectName = $projects.value[$i].name
    Write-Verbose -Verbose "updating Build definitions of project $projectName"

    # Get the existing Queues in the target TFS
    $getExistingQueuesUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/queues/?api-version=' + $apiVersion
    $existingQueues = Invoke-RestMethod -Uri $getExistingQueuesUrl -Method Get -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json"

    # Get the build definitions from source TFS
    $getBDsUrl = $sourceTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/build/definitions/?api-version=' + $apiVersion
    $BDs = (Invoke-RestMethod -Uri $getBDsUrl -Method Get -Headers @{Authorization = "Basic $encodedSourcePat"} -ContentType "application/json")

    for($j=0; $j -lt $BDs.count; $j++ )
    {
        $BdId = $BDs.value[$j].id
        $getBDUrl = $sourceTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/build/definitions/' + $BdId + '/?api-version=' + $apiVersion
        $BD = (Invoke-RestMethod -Uri $getBDUrl -Method Get -Headers @{Authorization = "Basic $encodedSourcePat"} -ContentType "application/json")
        $oldQueue = $BD.queue
        $queue = $existingQueues.value | Where-Object {$_.Name -eq $oldQueue.name}
        if ($queue -ne $null)
        { 
            # Update the Build Definition with new agent queue to the Target TFS
            $BD.queue = $queue
            $updateBDUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/build/definitions/' + $BdId + '/?api-version=' + $apiVersion
            $requestBody = $BD | ConvertTo-Json -Depth 15
            $updatedBD = Invoke-RestMethod -Uri $updateBDUrl -Method PUT -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json" -Body $requestBody
        } 
    }  
}
