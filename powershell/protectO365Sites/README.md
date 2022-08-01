# Protect O365 Sites Using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This PowerShell script adds Sites to an O365 Teams protection job. It takes as input a list of site names.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Begin download commands
$scriptName = 'protectO365Sites'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End download commands
```

## Components

* protectO365Sites.ps1: the main PowerShell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place all files in a folder together. You can provide a list of sites at the command line, or create a text file and populate with the team names (one per line), or you can automatically protect unprotected sites.

Then, run the main script like so:

To protect specific sites:

```powershell
# example - adding teams from the command line
./protectO365Sites.ps1 -vip mycluster `
                       -username myusername `
                       -domain mydomain.net `
                       -jobName 'My Job' `
                       -site my-site1, my-site2
# end example
```

To protect a list of sites from a text file:

```powershell
# example - adding teams from the command line
./protectO365Sites.ps1 -vip mycluster `
                       -username myusername `
                       -domain mydomain.net `
                       -jobName 'My Job' `
                       -sitelist ./mysites.txt
# end example
```

To protect automatically selected sites that are unprotected:

```powershell
# example - adding teams from a text file
./protectO365Sites.ps1 -vip mycluster `
                       -username myusername `
                       -domain mydomain.net `
                       -jobName 'My Job' `
                       -allSites
# end example
```

To create an autoprotect job that excludes sites that are already protected:

```powershell
# example - adding teams from a text file
./protectO365Sites.ps1 -vip mycluster `
                       -username myusername `
                       -domain mydomain.net `
                       -jobName 'My Job' `
                       -autoProtectRemaining
# end example
```

## Authentication Parameters

* -vip: (optional) name or IP of Cohesity cluster (defaults to helios.cohesity.com)
* -username: (optional) name of user to connect to Cohesity (defaults to helios)
* -domain: (optional) your AD domain (defaults to local)
* -useApiKey: (optional) use API key for authentication
* -password: (optional) will use cached password or will be prompted
* -mcm: (optional) connect through MCM
* -mfaCode: (optional) TOTP MFA code
* -emailMfaCode: (optional) send MFA code via email
* -clusterName: (optional) cluster to connect to when connecting through Helios or MCM

## Other Parameters

* -jobName: name of the O365 protection job to exclude mailboxes from
* -sites: (optional) a comma separated list of site names to protect
* -siteList: (optional) a text file list of site names to protect
* -allSites: (optional) protect unprotected sites (up to the maxSitesPerJob)
* -maxSitesPerJob: (optional) default is 5000
* -sourceName: (optional) name of registered O365 protection source (required for new job)
* -autoProtectRemaining: (optional) autoprotect at the source and exclude already protected sites
* -pageSize: (optional) discover X users per query (default is 1000)

## New Job Parameters

* -policyName: (optional) name of the protection policy to use
* -startTime: (optional) e.g. '18:30' (defaults to 8PM)
* -timeZone: (optional) e.g. 'America/New_York' (default is 'America/Los_Angeles')
* -incrementalSlaMinutes: (optional) default 60
* -fullSlaMinutes: (optional) default is 120
* -storageDomainName: (optional) default is 'DefaultStorageDomain'
* -paused: (optional) pause future runs (new job only)
* -disableIndexing: (optional) disable indexing (indexing is enabled by default)