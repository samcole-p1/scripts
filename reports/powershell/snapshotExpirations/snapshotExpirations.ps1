# process commandline arguments
[CmdletBinding()]
param (
    [Parameter()][string]$vip = 'helios.cohesity.com',
    [Parameter()][string]$username = 'helios',
    [Parameter()][string]$domain = 'local',
    [Parameter()][string]$tenant = $null,
    [Parameter()][switch]$useApiKey,
    [Parameter()][string]$password = $null,
    [Parameter()][switch]$noPrompt,
    [Parameter()][switch]$mcm,
    [Parameter()][string]$mfaCode = $null,
    [Parameter()][switch]$emailMfaCode,
    [Parameter()][string]$clusterName = $null,
    [Parameter()][array]$jobName,
    [Parameter()][string]$jobList,
    [Parameter()][int]$numRuns = 500
)

# source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

# authenticate
apiauth -vip $vip -username $username -domain $domain -passwd $password -apiKeyAuthentication $useApiKey -mfaCode $mfaCode -sendMfaCode $emailMfaCode -heliosAuthentication $mcm -regionid $region -tenant $tenant -noPromptForPassword $noPrompt

# select helios/mcm managed cluster
if($USING_HELIOS){
    if($clusterName){
        $thisCluster = heliosCluster $clusterName
    }else{
        Write-Host "Please provide -clusterName when connecting through helios" -ForegroundColor Yellow
        exit 1
    }
}

if(!$cohesity_api.authorized){
    Write-Host "Not authenticated" -ForegroundColor Yellow
    exit 1
}

# outfile
$cluster = api get cluster
$now = Get-Date
$dateString = $now.ToString('yyyy-MM-dd')
$outfileName = "snapshotExpirationReport-$($cluster.name)-$dateString.tsv"

# headings
$headings = "Cluster Name`tTenant`tJob Name`tEnvironment`tRun Type`tRun Start Time`tExpiration"
$headings | Out-File -FilePath $outfileName # -Encoding utf8


# gather list from command line params and file
function gatherList($Param=$null, $FilePath=$null, $Required=$True, $Name='items'){
    $items = @()
    if($Param){
        $Param | ForEach-Object {$items += $_}
    }
    if($FilePath){
        if(Test-Path -Path $FilePath -PathType Leaf){
            Get-Content $FilePath | ForEach-Object {$items += [string]$_}
        }else{
            Write-Host "Text file $FilePath not found!" -ForegroundColor Yellow
            exit
        }
    }
    if($Required -eq $True -and $items.Count -eq 0){
        Write-Host "No $Name specified" -ForegroundColor Yellow
        exit
    }
    return ($items | Sort-Object -Unique)
}


$jobNames = @(gatherList -Param $jobName -FilePath $jobList -Name 'jobs' -Required $false)

$jobs = api get -v2 "data-protect/protection-groups?includeTenants=true"

if($jobNames.Count -gt 0){
    $notfoundJobs = $jobNames | Where-Object {$_ -notin $jobs.protectionGroups.name}
    if($notfoundJobs){
        Write-Host "Jobs not found $($notfoundJobs -join ', ')" -ForegroundColor Yellow
        exit 1
    }
}

foreach($job in $jobs.protectionGroups | Sort-Object -Property name){
    $v1JobId = ($job.id -split ':')[2]
    $endUsecs = dateToUsecs (Get-Date)
    if($jobNames.Count -eq 0 -or $job.name -in $jobNames){
        $environment = $job.environment.subString(1)
        $tenant = $job.permissions.name
        "{0} ({1})" -f $job.name, $environment
        while($True){
            $runs = api get -v2 "data-protect/protection-groups/$($job.id)/runs?numRuns=$numRuns&endTimeUsecs=$endUsecs&includeTenants=true&includeObjectDetails=true"
            foreach($run in $runs.runs){
                if(! $run.PSObject.Properties['isLocalSnapshotsDeleted']){
                    if($run.PSObject.Properties['localBackupInfo']){
                        $backupInfo = $run.localBackupInfo
                    }else{
                        $backupInfo = $run.originalBackupInfo
                    }
                    $runType = $backupInfo.runType.subString(1)
                    if($runType -eq 'Regular'){
                        $runType = 'Incremental'
                    }
                    $runStartTime = usecsToDate $backupInfo.startTimeUsecs
                    "    {0} ({1})" -f $runStartTime, $runType
                    $runDetail = api get "/backupjobruns?allUnderHierarchy=true&exactMatchStartTimeUsecs=$($backupInfo.startTimeUsecs)&id=$($v1JobId)"
                    $expireTimeUsecs = $runDetail.backupJobRuns.protectionRuns[0].copyRun.finishedTasks[0].expiryTimeUsecs
                    $expiration = usecsToDate $expireTimeUsecs
                    "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f $cluster.name, $tenant, $job.name, $environment, $runType, $runStartTime, $expiration | Out-File -FilePath $outfileName -Append
                }
            }
            if($runs.runs.Count -eq $numRuns){
                $endUsecs = $runs.runs[-1].localBackupInfo.endTimeUsecs - 1
                if($endUsecs -lt 0 -or $endUsecs -lt $daysBackUsecs){
                    break
                }
            }else{
                break
            }
        }
    }
}

"`nOutput saved to $outfilename`n"