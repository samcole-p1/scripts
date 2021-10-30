# usage: ./protectPhysicalLinux.ps1 -vip mycluster -username myusername -jobName 'My Job' -serverList ./servers.txt -exclusionList ./exclusions.txt

# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$vip,  # the cluster to connect to (DNS name or IP)
    [Parameter(Mandatory = $True)][string]$username,  # username (local or AD)
    [Parameter()][string]$domain = 'local',  # local or AD domain
    [Parameter()][array]$servers = '',  # optional name of one server protect
    [Parameter()][string]$serverList = '',  # optional textfile of servers to protect
    [Parameter()][array]$inclusions = '', # optional paths to exclude (comma separated)
    [Parameter()][string]$inclusionList = '',  # optional list of exclusions in file
    [Parameter()][array]$exclusions = '',  # optional name of one server protect
    [Parameter()][string]$exclusionList = '',  # required list of exclusions
    [Parameter(Mandatory = $True)][string]$jobName,  # name of the job to add server to
    [Parameter()][switch]$skipNestedMountPoints,  # 6.3 and below - skip all nested mount points
    [Parameter()][array]$skipNestedMountPointTypes = @(),  # 6.4 and above - skip listed mount point types
    [Parameter()][switch]$replaceRules,
    [Parameter()][switch]$allServers
)

# gather list of servers to add to job
$serversToAdd = @()
foreach($server in $servers){
    $serversToAdd += $server
}
if ('' -ne $serverList){
    if(Test-Path -Path $serverList -PathType Leaf){
        $servers = Get-Content $serverList
        foreach($server in $servers){
            $serversToAdd += $server
        }
    }else{
        Write-Warning "Server list $serverList not found!"
        exit
    }
}

# gather inclusion list
$includePaths = @()
foreach($inclusion in $inclusions){
    $includePaths += $inclusion
}
if('' -ne $inclusionList){
    if(Test-Path -Path $inclusionList -PathType Leaf){
        $inclusions = Get-Content $inclusionList
        foreach($inclusion in $inclusions){
            $includePaths += $inclusion
        }
    }else{
        Write-Warning "Inclusions file $inclusionList not found!"
        exit
    }
}
if(! $includePaths){
    $includePaths += '/'
}

# gather exclusion list
$excludePaths = @()
foreach($exclusion in $exclusions){
    $excludePaths += $exclusion
}
if('' -ne $exclusionList){
    if(Test-Path -Path $exclusionList -PathType Leaf){
        $exclusions = Get-Content $exclusionList
        foreach($exclusion in $exclusions){
            $excludePaths += $exclusion
        }
    }else{
        Write-Warning "Exclusions file $exclusionList not found!"
        exit
    }
}

# skip nested mount points
if($skipNestedMountPoints){
    $skip = $True
}else{
    $skip = $false
}

# source the cohesity-api helper code
. $(Join-Path -Path $PSScriptRoot -ChildPath cohesity-api.ps1)

# authenticate
apiauth -vip $vip -username $username -domain $domain

# get the protectionJob
$jobs = api get -v2 "data-protect/protection-groups?isDeleted=false&isActive=true&environments=kPhysical&names=$jobName"
$job = $jobs.protectionGroups | Where-Object {$_.name -ieq $jobName}

if(!$job){
    Write-Host "Job $jobName not found!" -ForegroundColor Yellow
    exit
}

if($job.physicalParams.protectionType -ne 'kFile'){
    Write-Host "Job $jobName is not a file-based physical job!" -ForegroundColor Yellow
    exit
}

# get physical protection sources
$sources = api get protectionSources?environments=kPhysical

$sourceIds = [array]($job.physicalParams.fileProtectionTypeParams.objects.id)
$newSourceIds = @()

foreach($server in $serversToAdd | Where-Object {$_ -ne ''}){
    $server = $server.ToString()
    $node = $sources.nodes | Where-Object { $_.protectionSource.name -eq $server }
    if($node){
        if($node.registrationInfo.refreshErrorMessage -or $node.registrationInfo.authenticationStatus -ne 'kFinished'){
            Write-Warning "$server has source registration errors"
        }else{
            if($node.protectionSource.physicalProtectionSource.hostType -ne 'kWindows'){
                $sourceId = $node.protectionSource.id
                $newSourceIds += $sourceId
            }else{
                Write-Warning "$server is a Windows host"
            }
        }
    }else{
        Write-Warning "$server is not a registered source"
    }
}

foreach($sourceId in @([array]$sourceIds + [array]$newSourceIds) | Sort-Object -Unique){
    if($allServers -or $sourceId -in $newSourceIds){
        $params = $job.physicalParams.fileProtectionTypeParams.objects | Where-Object id -eq $sourceId
        $node = $sources.nodes | Where-Object { $_.protectionSource.id -eq $sourceId }
        Write-Host "processing $($node.protectionSource.name)"
        if(($null -eq $params) -or $replaceRules){
            $params = @{
                "id" = $sourceId;
                "name" = $node.protectionSource.name;
                "filePaths" = @();
                "usesPathLevelSkipNestedVolumeSetting" = $true;
                "nestedVolumeTypesToSkip" = $null;
                "followNasSymlinkTarget" = $false
            }
        }

        # skip nested mountpoint types
        if($sourceId -in $newSourceIds -or $replaceRules){
            if($skipNestedMountPointTypes.Count -gt 0){
                $params.usesPathLevelSkipNestedVolumeSetting = $false
                $params.nestedVolumeTypesToSkip = @($skipNestedMountPointTypes)
            }
        }

        # process include rules
        foreach($includePath in $includePaths | Where-Object {$_ -ne ''} | Sort-Object -Unique){
            $includePath = $includePath.ToString()
            $filePath = $params.filePaths | Where-Object includedPath -eq $includePath
            if(($null -eq $filePath) -or $replaceRules){
                $filePath = @{
                    "includedPath" = $includePath;
                    "skipNestedVolumes" = $skip;
                    "excludedPaths" = @()
                }
            }
            $params.filePaths = @($params.filePaths | Where-Object includedPath -ne $includePath) + $filePath
        }

        # process exclude rules
        foreach($excludePath in $excludePaths | Where-Object {$_ -and $_ -ne ''} | Sort-Object -Unique){
            $excludePath = $excludePath.ToString()
            $parentPath = $params.filePaths | Where-Object {$excludePath.contains($_.includedPath)} | Sort-Object -Property {$_.includedPath.Length} -Descending | Select-Object -First 1
            if($parentPath){
                $parentPath.excludedPaths = @($parentPath.excludedPaths | Where-Object {$_ -ne $excludePath}) + $excludePath
            }else{
                foreach($parentPath in $params.filePaths){
                    $parentPath.excludedPaths = @($parentPath.excludedPaths | Where-Object {$_ -ne $excludePath}) + $excludePath
                }
            }
        }

        # update params
        $job.physicalParams.fileProtectionTypeParams.objects = @($job.physicalParams.fileProtectionTypeParams.objects | Where-Object id -ne $sourceId) + $params
    }
    # $job | ConvertTo-Json -Depth 99
    $null = api put "data-protect/protection-groups/$($job.id)" $job -v2
}