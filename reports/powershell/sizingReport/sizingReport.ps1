### process commandline arguments
[CmdletBinding()]
param (
   [Parameter(Mandatory = $True)][string]$vip, #the cluster to connect to (DNS name or IP)
   [Parameter(Mandatory = $True)][string]$username, #username (local or AD)
   [Parameter()][string]$domain = 'local', #local or AD domain
   [Parameter()][ValidateSet('KiB','MiB','GiB','TiB')][string]$unit = 'MiB',
   [Parameter()][int]$daysBack = 7,
   [Parameter()][Int64]$numRuns = 100,
   [Parameter()][Int64]$backDays = 0
)

### source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

$conversion = @{'Kib' = 1024; 'MiB' = 1024 * 1024; 'GiB' = 1024 * 1024 * 1024; 'TiB' = 1024 * 1024 * 1024 * 1024}
function toUnits($val){
    return "{0:n0}" -f ($val/($conversion[$unit]))
}

### authenticate
apiauth -vip $vip -username $username -domain $domain

$finishedStates = @('Succeeded', 'Canceled', 'Failed', 'Warning')

$cluster = api get cluster
$dateString = (get-date).ToString('yyyy-MM-dd')
$objectFileName = "SizingReport-PerObject-$($cluster.name)-$dateString.csv"
"""Owner"",""Job Name"",""Job Type"",""Source Name"",""Logical $unit"",""Peak Read $unit"",""Last Day Read $unit"",""Read Over Days $unit"",""Avg Read $unit"",""Last Day Written $unit"",""Written Over Days $unit"",""Avg Written $unit"",""Days Collected"",""Daily Read Change Rate %"",""Daily Write Change Rate %"",""Avg Replica Queue Hours"",""Avg Replica Hours"",""Avg Logical Replicated"",""Avg Physical Replicated""" | Out-File -FilePath $objectFileName

$runningTasks = 0

$now = (Get-Date).AddDays(-$backDays)
$daysBackUsecs = dateToUsecs $now.AddDays(-$daysBack)

$jobStats = @{}
$workloadStats = @{}
$clusterStats = @{}
$archiveStats = @{}
$jobDays = @{}
$jobPolicies = @{}
$policyNames = @()

# list policies
$policyFileName = "SizingReport-Policies-$($cluster.name)-$dateString.txt"
$policies = (api get -v2 "data-protect/policies").policies
$frequentSchedules = @('Minutes', 'Hours', 'Days')

foreach($job in (api get -v2 "data-protect/protection-groups?isDeleted=false&includeTenants=true").protectionGroups | Sort-Object -Property name){
    $jobId = $job.id
    $jobName = $job.name
    "$jobName"
    $jobType = $job.environment.Substring(1)
    $policyName = '-'
    if($job.isActive -eq $True){
        $policy = $policies | Where-Object {$_.id -eq $job.policyId}
        $policyName = $policy.name
    }
    $jobPolicies[$jobName] = $policyName
    $policyNames = @($policyNames + $policyName)
    $stats = @{}
    $owners = @{}
    $endUsecs = dateToUsecs $now
    while($True){
        if($endUsecs -le $daysBackUsecs){
            break
        }
        $runs = api get -v2 "data-protect/protection-groups/$jobId/runs?endTimeUsecs=$endUsecs&includeTenants=true&includeObjectDetails=True&numRuns=$numRuns"
        if($runs.runs.Count -gt 0){
            $endUsecs = $runs.runs[-1].localBackupInfo.startTimeUsecs - 1
        }else{
            break
        }
        foreach($run in $runs.runs){
            $runId = $run.id
            if($run.PSObject.Properties['originalBackupInfo']){
                $runStartTimeUsecs = $run.originalBackupInfo.startTimeUsecs
            }else{
                $runStartTimeUsecs = $run.localBackupInfo.startTimeUsecs
            }
            if($runStartTimeUsecs -lt $daysBackUsecs){
                break
            }
            $jobDays[$jobName] = $runStartTimeUsecs
            # archive stats
            if($run.PSObject.Properties['archivalInfo']){
                $archiveQueuedTime = $run.archivalInfo.archivalTargetResults[0].queuedTimeUsecs
                $archiveStartTime = $run.archivalInfo.archivalTargetResults[0].startTimeUsecs
                $archiveEndTime = $run.archivalInfo.archivalTargetResults[0].endTimeUsecs
                $archiveDelay = ($archiveStartTime - $archiveQueuedTime) / 3600000000
                $archiveDuration = ($archiveEndTime - $archiveStartTime) / 3600000000
                $logicalArchived = 0
                $physicalArchived = 0
                $run.archivalInfo.archivalTargetResults.stats.logicalBytesTransferred | ForEach-Object {$logicalArchived += $_}
                $run.archivalInfo.archivalTargetResults.stats.physicalBytesTransferred | ForEach-Object {$physicalArchived += $_}
                if($jobName -notin $archiveStats.Keys){
                    $archiveStats[$jobName] = @()
                }
                $archiveStats[$jobName] += @{
                    'startTimeUsecs' = $runStartTimeUsecs;
                    'delay' = $archiveDelay;
                    'duration' = $archiveDuration;
                    'logicalArchived' = $logicalArchived;
                    'physicalArchived' = $physicalArchived
                }
            }
            # per object stats
            foreach($server in ($run.objects | Sort-Object -Property {$_.object.name})){
                $sourceName = $server.object.name
                if(!($run.environment -eq 'kAD' -and $server.object.objectType -eq 'kDomainController')){
                    if($server.PSObject.Properties['originalBackupInfo']){
                        $logicalBytes = $server.originalBackupInfo.snapshotInfo.stats.logicalSizeBytes
                        $bytesRead = $server.originalBackupInfo.snapshotInfo.stats.bytesRead
                        $bytesWritten = 0
                        if($server.PSObject.Properties['replicationInfo']){
                            $bytesWritten = $server.replicationInfo.replicationTargetResults.stats.physicalBytesTransferred
                        }
                        $owner = $run.originClusterIdentifier.clusterName
                    }else{
                        $logicalBytes = $server.localSnapshotInfo.snapshotInfo.stats.logicalSizeBytes
                        $bytesRead = $server.localSnapshotInfo.snapshotInfo.stats.bytesRead
                        $bytesWritten = $server.localSnapshotInfo.snapshotInfo.stats.bytesWritten
                        $owner = $cluster.name
                    }
                    $logicalReplicated = 0
                    $physicalReplicated = 0
                    $replicaDelay = 0
                    $replicaDuration = 0
                    if($server.PSObject.Properties['replicationInfo']){
                        $replicaQueuedTime = $server.replicationInfo.replicationTargetResults[0].queuedTimeUsecs
                        $replicaStartTime = $server.replicationInfo.replicationTargetResults[0].startTimeUsecs
                        $replicaEndTime = $server.replicationInfo.replicationTargetResults[0].endTimeUsecs
                        $replicaDelay = ($replicaStartTime - $replicaQueuedTime) / 3600000000
                        $replicaDuration = ($replicaEndTime - $replicaStartTime) / 3600000000
                        $server.replicationInfo.replicationTargetResults.stats.logicalBytesTransferred | ForEach-Object {$logicalReplicated += $_}
                        $server.replicationInfo.replicationTargetResults.stats.physicalBytesTransferred | ForEach-Object {$physicalReplicated += $_}
                    }
                    # per object stats
                    if($sourceName -notin $stats.Keys){
                        $stats[$sourceName] = @()
                    }
                    $stats[$sourceName] += @{'startTimeUsecs' = $runStartTimeUsecs;
                                             'dataRead' = $bytesRead;
                                             'dataWritten' = $bytesWritten;
                                             'logicalSize' = $logicalBytes;
                                             'replicaDelay' = $replicaDelay;
                                             'replicaDuration' = $replicaDuration;
                                             'logicalReplicated' = $logicalReplicated;
                                             'physicalReplicated' = $physicalReplicated
                                            }
                    $owners[$sourceName] = $owner
                }
            }
        }
    }
    foreach($sourceName in ($stats.Keys | sort)){
        "  $sourceName"
        $owner = $owners[$sourceName]

        # logical size
        $logicalSize = ($stats[$sourceName].logicalSize | Measure-Object -Maximum).Maximum

        # last 24 hours
        $midnight = (get-date -Hour 0 -Minute 0).AddDays(-$backDays)
        $midnightUsecs = dateToUsecs $midnight
        $lastDay = dateToUsecs ($midnight.AddDays(-1))
        $lastDayStats = $stats[$sourceName] | Where-Object {$_.startTimeUsecs -ge $lastDay -and $_.startTimeUsecs -lt $midnightUsecs}
        $lastDayDataRead = 0
        $lastDayStats.dataRead | foreach-object{ $lastDayDataRead += $_ }
        $lastDayDataWritten = 0
        $lastDayStats.dataWritten | ForEach-Object{ $lastDayDataWritten += $_}

        # last X days
        $xDays = dateToUsecs ((get-date -Hour 0 -Minute 0).AddDays(-($daysBack + $backDays)))
        $xDaysStats = $stats[$sourceName] | Where-Object {$_.startTimeUsecs -ge $xDays}
        $xDaysDataRead = 0
        $xDaysStats.dataRead | foreach-object{ $xDaysDataRead += $_ }
        $xDaysDataWritten = 0
        $xDaysStats.dataWritten | ForEach-Object{ $xDaysDataWritten += $_}
        $peakRead = ($xDaysStats.dataRead | Measure-Object -Maximum).Maximum
        $xDaysReplicaDelay = 0
        $xDaysStats.replicaDelay | foreach-object{ $xDaysReplicaDelay += $_ }
        $xDaysLogicalReplicated = 0
        $xDaysStats.logicalReplicated | foreach-object { $xDaysLogicalReplicated += $_ }
        $xDaysPhysicalReplicated = 0
        $xDaysStats.physicalReplicated | foreach-object { $xDaysPhysicalReplicated += $_ }
        $xDaysReplicaDuration = 0
        $xDaysStats.replicaDuration | foreach-object { $xDaysReplicaDuration += $_ }

        # number of days gathered
        $oldestStat = usecsToDate $stats[$sourceName][-1]['startTimeUsecs']
        $numDays = ($now - $oldestStat).Days + 1

        # change rate
        if($logicalSize -gt 0){
            $changeRate = [math]::Round((100 * $xDaysDataRead / $logicalSize) / $numDays, 0)
            $writeChangeRate = [math]::Round((100 * $xDaysDataWritten/ $logicalSize) / $numDays, 0)
        }else{
            $changeRate = '-'
            $writeChangeRate = '-'
        }

        $avgDataRead = [math]::Round($xDaysDataRead / $numDays, 2)
        $avgDataWritten = [math]::Round($xDaysDataWritten / $numDays, 2)
        $avgReplicaDelay = [math]::Round($xDaysReplicaDelay / $numDays, 0)
        $avgReplicaDuration = [math]::Round($xDaysReplicaDuration / $numDays, 0)
        $avgLogicalReplicated = [math]::Round($xDaysLogicalReplicated / $numDays, 2)
        $avgPhysicalReplicated = [math]::Round($xDaysPhysicalReplicated / $numDays, 2)

        """{0}"",""{1}"",""{2}"",""{3}"",""{4}"",""{5}"",""{6}"",""{7}"",""{8}"",""{9}"",""{10}"",""{11}"",""{12}"",""{13}"",""{14}"",""{15}"",""{16}"",""{17}"",""{18}""" -f $owner, $jobName, $jobType, $sourceName, $(toUnits $logicalSize), $(toUnits $peakRead), $(toUnits $lastDayDataRead), $(toUnits $xDaysDataRead), $(toUnits $avgDataRead), $(toUnits $lastDayDataWritten), $(toUnits $xDaysDataWritten), $(toUnits $avgDataWritten), $numDays, $changeRate, $writeChangeRate, $avgReplicaDelay, $avgReplicaDuration, $(toUnits $avgLogicalReplicated), $(toUnits $avgPhysicalReplicated) | Out-File -FilePath $objectFileName -Append

        # per job stats
        if($jobName -notin $jobStats.Keys){
            $jobStats[$jobName] = @{
                'owner' = $owner;
                'jobType' = $jobType;
                'avgDataWritten' = $avgDataWritten;
                'avgDataRead' = $avgDataRead;
                'logicalSize' = $logicalSize;
                'avgLogicalReplicated' = $avgLogicalReplicated;
                'avgPhysicalReplicated' = $avgPhysicalReplicated
            }
        }else{
            $jobStats[$jobName].avgDataWritten += $avgDataWritten
            $jobStats[$jobName].avgDataRead += $avgDataRead
            $jobStats[$jobName].logicalSize += $logicalSize
            $jobStats[$jobName].avgLogicalReplicated += $avgLogicalReplicated
            $jobStats[$jobName].avgPhysicalReplicated += $avgPhysicalReplicated
        }
    }
}

# Per Job Stats
$jobFileName = "SizingReport-PerJob-$($cluster.name)-$dateString.csv"

"""Owner"",""JobName"",""JobType"",""Policy"",""Logical $unit"",""Avg Read $unit"",""Avg Written $unit"",""Read Change Rate"",""Write Change Rate"",""Avg Logical Replicated $unit"",""Avg Physical Replicated $unit"",""Avg Logical Archived $unit"",""Avg Physical Archived $unit""" | Out-File -FilePath $jobFileName 
foreach($jobName in ($jobStats.Keys | sort)){
    $owner = $jobStats[$jobName].owner
    $jobType = $jobStats[$jobName].jobType
    $logicalSize = 0
    $avgDataRead = 0
    $avgDataWritten = 0
    $avgLogicalReplicated = 0
    $avgPhysicalReplicated = 0
    $avgLogicalArchived = 0
    $avgPhysicalArchived = 0
    $logicalSize = $jobStats[$jobName].logicalSize
    $avgDataRead = $jobStats[$jobName].avgDataRead
    $avgDataWritten = $jobStats[$jobName].avgDataWritten
    $avgLogicalReplicated = $jobStats[$jobName].avgLogicalReplicated
    $avgPhysicalReplicated = $jobStats[$jobName].avgPhysicalReplicated
    if($jobName -in $archiveStats.Keys){
        $archiveStats[$jobName].logicalArchived | ForEach-Object { $avgLogicalArchived += $_ }
        $archiveStats[$jobName].physicalArchived | ForEach-Object {$avgPhysicalArchived += $_ }
        $oldestStat = usecsToDate $jobDays[$jobName]
        $numDays = ($now - $oldestStat).Days + 1
        $avgLogicalArchived = [math]::Round($avgLogicalArchived / $numDays, 0)
        $avgPhysicalArchived = [math]::Round($avgPhysicalArchived / $numDays, 0)
    }
    # workload stats
    if("$($owner)--$($jobType)" -notin $workloadStats.Keys){
        $workloadStats["$($owner)--$($jobType)"] = @{
            'logicalSize' = $logicalSize;
            'avgDataRead' = $avgDataRead;
            'avgDataWritten' = $avgDataWritten;
            'avgLogicalReplicated' = $avgLogicalReplicated;
            'avgPhysicalReplicated' = $avgPhysicalReplicated;
            'avgLogicalArchived' = $avgLogicalArchived;
            'avgPhysicalArchived' = $avgPhysicalArchived
        }
    }else{
        $workloadStats["$($owner)--$($jobType)"].logicalSize += $logicalSize
        $workloadStats["$($owner)--$($jobType)"].avgDataRead += $avgDataRead
        $workloadStats["$($owner)--$($jobType)"].avgDataWritten += $avgDataWritten
        $workloadStats["$($owner)--$($jobType)"].avgLogicalReplicated += $avgLogicalReplicated
        $workloadStats["$($owner)--$($jobType)"].avgPhysicalReplicated += $avgPhysicalReplicated
        $workloadStats["$($owner)--$($jobType)"].avgLogicalArchived += $avgLogicalArchived
        $workloadStats["$($owner)--$($jobType)"].avgPhysicalArchived += $avgPhysicalArchived
    }
    if($logicalSize -gt 0){
        $changeRate = [math]::Round(100 * $avgDataRead / $logicalSize, 0)
        $writeChangeRate = [math]::Round(100 * $avgDataWritten / $logicalSize, 0)
    }else{
        $changeRate = '-'
        $writeChangeRate = '-'
    }
    """{0}"",""{1}"",""{2}"",""{3}"",""{4}"",""{5}"",""{6}"",""{7}"",""{8}"",""{9}"",""{10}"",""{11}"",""{12}""" -f $owner, $jobName, $jobType, $jobPolicies[$jobName], $(toUnits $logicalSize), $(toUnits $avgDataRead), $(toUnits $avgDataWritten), $changeRate, $writeChangeRate, $(toUnits $avgLogicalReplicated), $(toUnits $avgPhysicalReplicated), $(toUnits $avgLogicalArchived), $(toUnits $avgPhysicalArchived) | Out-File -FilePath $jobFileName -Append
}

# Per Workload Stats
$workloadFileName = "SizingReport-PerWorkload-$($cluster.name)-$dateString.csv"

"""Owner"",""JobType"",""Logical $unit"",""Avg Read $unit"",""Avg Written $unit"",""Read Change Rate"",""Write Change Rate""" | Out-File -FilePath $workloadFileName

foreach($keyName in ($workloadStats.Keys | sort)){
    $owner, $jobType = $keyName.split('--')
    $logicalSize = $workloadStats[$keyName].logicalSize
    $avgDataRead = $workloadStats[$keyName].avgDataRead
    $avgDataWritten = $workloadStats[$keyName].avgDataWritten
    if($logicalSize -gt 0){
        $changeRate = [math]::Round(100 * $avgDataRead / $logicalSize, 0)
        $writeChangeRate = [math]::Round(100 * $avgDataWritten / $logicalSize, 0)
    }else{
        $changeRate = '-'
        $writeChangeRate = '-'
    }
    """{0}"",""{1}"",""{2}"",""{3}"",""{4}"",""{5}"",""{6}""" -f $owner, $jobType, $(toUnits $logicalSize), $(toUnits $avgDataRead), $(toUnits $avgDataWritten), $changeRate, $writeChangeRate | Out-File -FilePath $workloadFileName -Append
}

# Policy Info
"" | Out-File -FilePath $policyFileName
foreach($policy in $policies | Where-Object {$_.name -in $policyNames}){
    "         Policy Name: $($policy.name)" | Out-File -FilePath $policyFileName -Append
    # base retention
    $baseRetention = $policy.backupPolicy.regular.retention
    $dataLock = ''
    if($baseRetention.PSObject.Properties['dataLockConfig'] -and $baseRetention.dataLockConfig -ne $null){
        $dataLock = ", datalock for {0} {1}" -f $baseRetention.dataLockConfig.duration, $baseRetention.dataLockConfig.unit
    }
    if($policy.PSObject.Properties['dataLock']){
        $dataLock = ", datalock for {0} {1}" -f $baseRetention.duration, $baseRetention.unit
    }       
    # incremental backup
    if($policy.backupPolicy.regular.PSObject.Properties['incremental']){
        $backupSchedule = $policy.backupPolicy.regular.incremental.schedule
        $punit = $backupSchedule.unit
        $unitPath = "{0}Schedule" -f $punit.Tolower().Substring(0,$($punit.Length - 1))
        if($punit -in $frequentSchedules){
            $frequency = $backupSchedule.$unitPath.frequency
            "  Incremental backup: Every {0} {1} (keep for {2} {3}{4})" -f $frequency, $punit, $baseRetention.duration, $baseRetention.unit, $dataLock | Out-File -FilePath $policyFileName -Append
        }else{
            if($punit -eq 'Weeks'){
                "  Incremental backup: Weekly on {0} (keep for {1} {2}{3})" -f $($backupSchedule.$unitPath.dayOfWeek -join ', '), $baseRetention.duration, $baseRetention.unit, $dataLock | Out-File -FilePath $policyFileName -Append
            }
            if($punit -eq 'Months'){
                "  Incremental backup: Monthly on the {0} {1} (keep for {2} {3}{4})" -f $backupSchedule.$unitPath.weekOfMonth, $backupSchedule.$unitPath.dayOfWeek[0], $baseRetention.duration, $baseRetention.unit, $dataLock | Out-File -FilePath $policyFileName -Append
            }
        }
    }

    # full backup
    if($policy.backupPolicy.regular.PSObject.Properties['full']){
        $backupSchedule = $policy.backupPolicy.regular.full.schedule
        $punit = $backupSchedule.unit
        $unitPath = "{0}Schedule" -f $punit.ToLower().subString(0,$($punit.Length - 1))
        if($punit -in $frequentSchedules){
            $frequency = $backupSchedule.$unitPath.frequency
            "         Full backup: Every {0} {1} (keep for {2} {3}" -f $frequency, $punit, $baseRetention.duration, $baseRetention.unit | Out-File -FilePath $policyFileName -Append
        }else{
            if($punit -eq 'Weeks'){
                "         Full backup: Weekly on {0} (keep for {1} {2})" -f $($backupSchedule.$unitPath.dayOfWeek -join ', '), $baseRetention.duration, $baseRetention.unit | Out-File -FilePath $policyFileName -Append
            }
            if($punit -eq 'Months'){
                "         Full backup: Monthly on the {0} {1} (keep for {2} {3})" -f $backupSchedule.$unitPath.weekOfMonth, $backupSchedule.$unitPath.dayOfWeek[0], $baseRetention.duration, $baseRetention.unit | Out-File -FilePath $policyFileName -Append
            }
            if($punit -eq 'ProtectOnce'){
                "         Full backup: Once (keep for {0} {1})" -f $baseRetention.duration, $baseRetention.unit  | Out-File -FilePath $policyFileName -Append
            }
        }
    }
    # extended retention
    if($policy.PSObject.Properties['extendedRetention'] -and $policy.extendedRetention -ne $null -and $policy.extendedRetention.Count -gt 0){
        "  Extended retention:" | Out-File -FilePath $policyFileName -Append
        foreach($extendedRetention in $policy.extendedRetention){
            "                      Every {0} {1} (keep for {2} {3})" -f $extendedRetention.schedule.frequency, $extendedRetention.schedule.unit, $extendedRetention.retention.duration, $extendedRetention.retention.unit | Out-File -FilePath $policyFileName -Append
        }
    }
    # log backup
    if($policy.backupPolicy.PSObject.Properties['log']){
        $logRetention = $policy.backupPolicy.log.retention
        $backupSchedule = $policy.backupPolicy.log.schedule
        $punit = $backupSchedule.unit
        $unitPath = "{0}Schedule" -f $punit.ToLower().subString(0,$($punit.Length - 1))
        $frequency = $backupSchedule.$unitPath.frequency
        "          Log backup: Every {0} {1} (keep for {2} {3})" -f $frequency, $punit, $logRetention.duration, $logRetention.unit | Out-File -FilePath $policyFileName -Append
    }
    # remote targets
    if($policy.PSObject.Properties['remoteTargetPolicy'] -and $policy.remoteTargetPolicy -ne $null -and $policy.remoteTargetPolicy.Count -gt 0){
        # replication targets
        if($policy.remoteTargetPolicy.PSObject.Properties['replicationTargets'] -and $policy.remoteTargetPolicy.replicationTargets -ne $null -and $policy.remoteTargetPolicy.replicationTargets.Count -gt 0){
            "        Replicate To:" | Out-File -FilePath $policyFileName -Append
            foreach($replicationTarget in $policy.remoteTargetPolicy.replicationTargets){
                if($replicationTarget.targetType -eq 'RemoteCluster'){
                    $targetName = $replicationTarget.remoteTargetConfig.clusterName
                }else{
                    $targetName = $replicationTarget.targetType
                }
                $frequencyunit = $replicationTarget.schedule.unit
                if($frequencyunit -eq 'Runs'){
                    $frequencyunit = 'Run'
                    $frequency = 1
                }else{
                    $frequency = $replicationTarget.schedule.frequency
                }
                "                      {0}: Every {1} {2} (keep for {3} {4})" -f $targetName, $frequency, $frequencyunit, $replicationTarget.retention.duration, $replicationTarget.retention.unit | Out-File -FilePath $policyFileName -Append
            }
        }
        if($policy.remoteTargetPolicy.PSObject.Properties['archivalTargets'] -and $policy.remoteTargetPolicy.archivalTargets -ne $null -and $policy.remoteTargetPolicy.archivalTargets.Count -gt 0){
            "          Archive To:" | Out-File -FilePath $policyFileName -Append
            foreach($archivalTarget in $policy.remoteTargetPolicy.archivalTargets){
                $frequencyunit = $archivalTarget.schedule.unit
                if($frequencyunit -eq 'Runs'){
                    $frequencyunit = 'Run'
                    $frequency = 1
                }else{
                    $frequency = $archivalTarget.schedule.frequency
                }
                "                      {0}: Every {1} {2} (keep for {3} {4})" -f $archivalTarget.targetName, $frequency, $frequencyunit, $archivalTarget.retention.duration, $archivalTarget.retention.unit | Out-File -FilePath $policyFileName -Append
            }
        }
    }
    "`n`n" | Out-File -FilePath $policyFileName -Append
}

"`n  Per Object Stats saved to: {0}" -f $objectFileName
"     Per Job Stats saved to: {0}" -f $jobFileName
"Per Workload Stats saved to: {0}" -f $workloadFileName
"       Policy Info saved to: {0}`n" -f $policyFileName
