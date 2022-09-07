# Control Marketplace App Instances using PowerShell

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This powershell script can display, pause, resume and terminate marketplace app instances.

## Download the script

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Begin download commands
$scriptName = 'marketplaceApps'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -UseBasicParsing -Uri "$repoUrl/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
# End download commands
```

## Components

* marketplaceApps.ps1: the main powershell script
* cohesity-api.ps1: the Cohesity REST API helper module

Place both files in a folder together and run the main script like so:

To list app instances:

```powershell
#example
./marketplaceApps.ps1 -vip mycluster `
                      -username myusername `
                      -domain mydomain.net
#end example
```

To pause some app instances:

```powershell
#example
./marketplaceApps.ps1 -vip mycluster `
                      -username myusername `
                      -domain mydomain.net `
                      -pause 'My App', 'My Other App'
#end example
```

To resume some app instances:

```powershell
#example
./marketplaceApps.ps1 -vip mycluster `
                      -username myusername `
                      -domain mydomain.net `
                      -resume 'My App', 'My Other App'
#end example
```

To terminate some app instances:

```powershell
#example
./marketplaceApps.ps1 -vip mycluster `
                      -username myusername `
                      -domain mydomain.net `
                      -terminate 'My App', 'My Other App'
#end example
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

* -pause: (optional) one or more app names to pause (comma separated)
* -resume: (optional) one or more app names to resume (comma separated)
* -terminate: (optional) one or more app names to stop (comma separated)
* -wait: (optional) wait for apps to complete transitional states