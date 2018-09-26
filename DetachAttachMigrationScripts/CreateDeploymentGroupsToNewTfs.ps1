<# 
This script is applicable for TFS 2018 or later.
This is a guidance script to create deployment groupa to the target TFS after detach\attach activity. The script is applicable if both source and target TFS is accessibile and

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

    # Get the existing Deployment Pools
    $getDeploymentPoolsUrl = $targetTFSUrl + '/_apis/distributedtask/pools/?pooltype=2&api-version=' + $apiVersion
    $existingDPs = Invoke-RestMethod -Uri $getDeploymentPoolsUrl -Method Get -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json"

    # Get the existing Deployment Groups
    $getDeploymentGroupsUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/deploymentgroups/?api-version=' + $apiVersion
    $existingDGs = Invoke-RestMethod -Uri $getDeploymentGroupsUrl -Method Get -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json"

    # Get the Deployment Groups in the source project
    Write-Verbose -Verbose "Getting Deployment groups in project $projectName"
    $getDeploymentGroupsUrl = $sourceTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/deploymentgroups/?api-version=' + $apiVersion
    $dgs = Invoke-RestMethod -Uri $getDeploymentGroupsUrl -Method Get -Headers @{Authorization = "Basic $encodedSourcePat"} -ContentType "application/json"

    for($j=0; $j -lt $dgs.count; $j++ )
    {
        $dg = $dgs.value[$j]
        $dgName = $dg.name 
        $existingDG = $existingDGs.value | Where-Object {$_.Name -eq $dg.name}
        if ($existingDG -ne $null)
        {
            Write-Verbose -Verbose "Deployment group $dgName is already present in the the project $projectName of the target TFS $targetTFSUrl."
        }
        else
        {
            $dp = $existingDPs.value | Where-Object {$_.Name -eq $dg.pool.name}
            if ($dp -eq $null)
            {
                $poolName = $dg.pool.name
                Write-Verbose -Verbose "Creating a deployment pool with name $poolName on the target TFS $targetTFSUrl."
                $pool = @{'name' = $poolName; 'PoolType' = 2; 'AutoProvision'= $false} | ConvertTo-Json
                $createDeploymentPoolUrl = $targetTFSUrl + '/_apis/distributedtask/pools/?pooltype=2&api-version=' + $apiVersion
                $dp = Invoke-RestMethod -Uri $createDeploymentPoolUrl -Method POST -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json" -Body $pool
            }

            Write-Verbose -Verbose "Creating a deployment group with name $dgName on the target TFS $targetTFSUrl."
            $dgBody = @{'name' = $dgName; 'pool' = @{'id' = $dp.id}} | ConvertTo-Json
            $createDeploymentGroupsUrl = $targetTFSUrl + '/' + $collectionName + '/' + $projectName + '/_apis/distributedtask/deploymentgroups/?api-version=' + $apiVersion
            Invoke-RestMethod -Uri $createDeploymentGroupsUrl -Method POST -Headers @{Authorization = "Basic $encodedTargetPat"} -ContentType "application/json" -Body $dgBody
        }
    }
}
