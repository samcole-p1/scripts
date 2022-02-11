# Mask and Clone a SQL Database using a SQL Agent Job

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This demonstrates how to mask and clone a SQL database using a SQL Agent job.

## Download the scripts

Run these commands from PowerShell to download the script(s) into your current directory

```powershell
# Download Commands
$scriptName = 'backupNow'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master'
(Invoke-WebRequest -Uri "$repoUrl/powershell/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
$scriptName = 'cloneSQL'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master'
(Invoke-WebRequest -Uri "$repoUrl/sql/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
$scriptName = 'destroyClone'
(Invoke-WebRequest -Uri "$repoUrl/sql/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
$scriptName = 'refreshSource'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/powershell'
(Invoke-WebRequest -Uri "$repoUrl/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
$scriptName = 'restoreSQL'
$repoURL = 'https://raw.githubusercontent.com/bseltz-cohesity/scripts/master'
(Invoke-WebRequest -Uri "$repoUrl/sql/$scriptName/$scriptName.ps1").content | Out-File "$scriptName.ps1"; (Get-Content "$scriptName.ps1") | Set-Content "$scriptName.ps1"
(Invoke-WebRequest -Uri "$repoUrl/powershell/cohesity-api/cohesity-api.ps1").content | Out-File cohesity-api.ps1; (Get-Content cohesity-api.ps1) | Set-Content cohesity-api.ps1
(Invoke-WebRequest -Uri "$repoUrl/sql/sqlAgentJob-cloneDB/createCloneSQLAgentJob.sql").content | Out-File createCloneSQLAgentJob.sql; (Get-Content createCloneSQLAgentJob.sql) | Set-Content createCloneSQLAgentJob.sql
# End Download Commands
```

## Components

* backupNow.ps1: run a backup
* cloneSQL.ps1: clone a SQL database
* destroyClone.ps1: tear down an existing clone
* cohesity-api.ps1: the Cohesity REST API helper module
* createMaskerSQLAgentJob.sql: T-SQL to create the SQL Agent Job
* refreshSource.ps1: refresh a protection source
* restoreSQL.ps1: restore a SQL database

## Creating the SQL Agent Job

Open SSMS and open the createMaskerSQLAgentJob.sql in a query window, review it and execute it. It should create a new SQL Agent job called 'Mask DB'

The job has several steps:

1) Restore a production database to a database called "masker"
2) Perform some T-SQL (place holder for masking process)
3) Refresh the protection source to detect the new masker DB
4) Backup the masker DB
5) Tear down an existing clone (if any)
6) Create a new clone of the masked DB.

Edit the steps and adjust the commands to suite your environment.

## Authentication to Cohesity

The username and domain parameters in the scripts (as called in the SQL Agent job steps) must have the correct access defined in Cohesity. No privileged access is required on the SQL server where the job is executed.

To make these scripts run unattended, we must store the cohesity user's password. This will be stored as an encrypted secure string accessible only by the Windows account that the SQL Agent service runs as.

To get the password stored, remote desktop into the SQL server as the SQL Agent service user. Alternatively, you can shift-right-click the PowerShell icon and "run as a different user", and use the SQL Agent servicee user. Then simply run one of the PowerShell scripts in the SQL agent job, from the PowerShell command line. You will be prompted to enter the password, after which the password will be stored for future use. Then, the SQL agent job will be able to run without being prompted for a password.

## Additional Command Line Parameters

Both of the PowerShell scripts included in this package have various command line parameters. You can find them here:

* cloneSQL.ps1: <https://github.com/bseltz-cohesity/scripts/tree/master/sql/cloneSQL>
* destroyClone.ps1: <https://github.com/bseltz-cohesity/scripts/tree/master/sql/destroyClone>