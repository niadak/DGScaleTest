<# 
This script is applicable for TFS 2018 or later.
This is a guidance script to update Release defifinitions to the target TFS with new AgentQueues/DeploymentGroups after detach\attach activity.
The script is applicable if both source and target TFS are accessibile and AgentQueues and DeploymentGroups are migrated to the target TFS

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
    Write-Verbose -Verbose "updating Release definitions of project $projectName"

    # Get the existing Queues in the target TFS
    $getExistingQueuesUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/queues/?api-version=' + $apiVersion
    $existingQueues = Invoke-RestMethod -Uri $getExistingQueuesUrl -Method Get -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json"

    # Get the existing Deployment Groups in the target TFS
    $getDeploymentGroupsUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/deploymentgroups/?api-version=' + $apiVersion
    $existingDGs = Invoke-RestMethod -Uri $getDeploymentGroupsUrl -Method Get -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json"

    # Get the existing Queues in the source TFS
    $getExistingQueuesUrl = $sourceTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/queues/?api-version=' + $apiVersion
    $existingQueuesInSource = Invoke-RestMethod -Uri $getExistingQueuesUrl -Method Get -Headers @{Authorization = "Basic $encodedSourcePat"} -ContentType "application/json"

    # Get the existing Deployment Groups in the source TFS
    $getDeploymentGroupsUrl = $sourceTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/deploymentgroups/?api-version=' + $apiVersion
    $existingDGsInSource = Invoke-RestMethod -Uri $getDeploymentGroupsUrl -Method Get -Headers @{Authorization = "Basic $encodedSourcePat"} -ContentType "application/json"

    # Get the release definitions from source TFS
    $getRDsUrl = $sourceTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/Release/definitions/?api-version=' + $apiVersion
    $RDs = (Invoke-RestMethod -Uri $getRDsUrl -Method Get -Headers @{Authorization = "Basic $encodedSourcePat"} -ContentType "application/json")

    for($j=0; $j -lt $RDs.count; $j++ )
    {
        $RdId = $RDs.value[$j].id
        $getRDUrl = $sourceTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/Release/definitions/' + $RdId + '/?api-version=' + $apiVersion
        $RD = (Invoke-RestMethod -Uri $getRDUrl -Method Get -Headers @{Authorization = "Basic $encodedSourcePat"} -ContentType "application/json")
        $updatedRD = $RD
        for ($k=0; $k -lt $RD.environments.Count; $k++)
        {
            $env = $RD.environments[$k];
            for ($l=0; $l -lt $env.deployPhases.count; $l++)
            {
                $phase = $env.deployPhases[$l];
                $oldQueueId = $phase.deploymentInput.queueId
                if ($phase.phaseType -eq 'agentBasedDeployment')
                {
                    $queue = $existingQueuesInSource.value | Where-Object {$_.Id -eq $oldQueueId}
                    $existingQueue = $existingQueues.value | Where-Object {$_.Name -eq $queue.name}
                    $updatedRD.environments[$k].deployPhases[$l].deploymentInput.queueId = $existingQueue.id
                }

                if ($phase.phaseType -eq 'machineGroupBasedDeployment')
                {
                    $dg = $existingDGsInSource.value | Where-Object {$_.Id -eq $oldQueueId}
                    $existingDg = $existingDGs.value | Where-Object {$_.Name -eq $dg.name}
                    $updatedRD.environments[$k].deployPhases[$l].deploymentInput.queueId = $existingDg.id
                }
            }
        }

        $updateRDUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/Release/definitions/' + $RdId + '/?api-version=' + $apiVersion
        $requestBody = $updatedRD | ConvertTo-Json -Depth 15
        $latestRD = Invoke-RestMethod -Uri $updateRDUrl -Method PUT -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json" -Body $requestBody
    }  
}
