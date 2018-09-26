<# 
This script is applicable for TFS 2018 or later.
This is a guidance script to create agent queues to the target TFS after detach\attach activity. The script is applicable if both source and target TFS is accessibile.

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
$apiVersion = '5.0-preview.1'

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
    Write-Verbose -Verbose "Migrating deployment groups of project $projectName"

    # Get the existing Agent Pools
    $getAgentPoolsUrl = $targetTFSUrl + '/_apis/distributedtask/pools/?api-version=' + $apiVersion
    $existingAPs = Invoke-RestMethod -Uri $getAgentPoolsUrl -Method Get -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json"

    # Get the existing Queues
    $getExistingQueuesUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/queues/?api-version=' + $apiVersion
    $existingQueues = Invoke-RestMethod -Uri $getExistingQueuesUrl -Method Get -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json"

    # Get the Queues in the source project
    Write-Verbose -Verbose "Getting Queues in project $projectName"
    $getQueuesUrl = $sourceTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/queues/?api-version=' + $apiVersion
    $queues = Invoke-RestMethod -Uri $getQueuesUrl -Method Get -Headers @{Authorization = "Basic $encodedSourcePat"} -ContentType "application/json"

    for($j=0; $j -lt $queues.count; $j++ )
    {
        $queue = $queues.value[$j]
        $queueName = $queue.name
        $existingQueue = $existingQueues.value | Where-Object {$_.Name -eq $queue.name}
        if ($existingQueue -ne $null)
        { 
            Write-Verbose -Verbose "Queue $queueName is already present in the the project $projectName of the target TFS $targetTFSUrl."
        }
        else
        {
            $ap = $existingAPs.value | Where-Object {$_.Name -eq $queue.pool.name}
            if ($ap -eq $null)
            {
                $poolName = $queue.pool.name
                Write-Verbose -Verbose "Creating a agent pool with name $poolName on the target TFS $targetTFSUrl."
                $pool = @{'name' = $poolName;'AutoProvision'= $false} | ConvertTo-Json
                $createPoolUrl = $targetTFSUrl + '/_apis/distributedtask/pools/?api-version=' + $apiVersion
                $ap = Invoke-RestMethod -Uri $createPoolUrl -Method POST -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json" -Body $pool
            }

            Write-Verbose -Verbose "Creating a deployment group with name $queueName in the the project $projectName of the target TFS $targetTFSUrl."
            $queueBody = @{'name' = $queueName; 'pool' = @{'id' = $ap.id}} | ConvertTo-Json
            $createQueueUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/queues/?api-version=' + $apiVersion
            Invoke-RestMethod -Uri $createQueueUrl -Method POST -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json" -Body $queueBody
        }
    }
}
