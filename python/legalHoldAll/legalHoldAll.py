#!/usr/bin/env python
"""base V1 example"""

# import pyhesity wrapper module
from pyhesity import *
from datetime import datetime

# command line arguments
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('-v', '--vip', type=str, default='helios.cohesity.com')
parser.add_argument('-u', '--username', type=str, default='helios')
parser.add_argument('-d', '--domain', type=str, default='local')
parser.add_argument('-t', '--tenant', type=str, default=None)
parser.add_argument('-c', '--clustername', type=str, default=None)
parser.add_argument('-mcm', '--mcm', action='store_true')
parser.add_argument('-i', '--useApiKey', action='store_true')
parser.add_argument('-pwd', '--password', type=str, default=None)
parser.add_argument('-np', '--noprompt', action='store_true')
parser.add_argument('-m', '--mfacode', type=str, default=None)
parser.add_argument('-j', '--jobname', action='append', type=str)
parser.add_argument('-l', '--joblist', type=str)
parser.add_argument('-n', '--numruns', type=int, default=1000)
parser.add_argument('-a', '--addhold', action='store_true')
parser.add_argument('-r', '--removehold', action='store_true')

args = parser.parse_args()

vip = args.vip
username = args.username
domain = args.domain
tenant = args.tenant
clustername = args.clustername
mcm = args.mcm
useApiKey = args.useApiKey
password = args.password
noprompt = args.noprompt
mfacode = args.mfacode
jobnames = args.jobname
joblist = args.joblist
numruns = args.numruns
addhold = args.addhold
removehold = args.removehold

# authenticate
apiauth(vip=vip, username=username, domain=domain, password=password, useApiKey=useApiKey, helios=mcm, prompt=(not noprompt), mfaCode=mfacode, tenantId=tenant)

# if connected to helios or mcm, select access cluster
if mcm or vip.lower() == 'helios.cohesity.com':
    if clustername is not None:
        heliosCluster(clustername)
    else:
        print('-clustername is required when connecting to Helios or MCM')
        exit()

# exit if not authenticated
if apiconnected() is False:
    print('authentication failed')
    exit(1)

now = datetime.now()
nowUsecs = dateToUsecs(now.strftime("%Y-%m-%d %H:%M:%S"))

# outfile
cluster = api('get', 'cluster')


# gather server list
def gatherList(param=None, filename=None, name='items', required=True):
    items = []
    if param is not None:
        for item in param:
            items.append(item)
    if filename is not None:
        f = open(filename, 'r')
        items += [s.strip() for s in f.readlines() if s.strip() != '']
        f.close()
    if required is True and len(items) == 0:
        print('no %s specified' % name)
        exit()
    return items


jobnames = gatherList(jobnames, joblist, name='jobs', required=False)

jobs = api('get', 'protectionJobs')

# catch invalid job names
notfoundjobs = [n for n in jobnames if n.lower() not in [j['name'].lower() for j in jobs]]
if len(notfoundjobs) > 0:
    print('Jobs not found: %s' % ', '.join(notfoundjobs))
    exit(1)

if addhold:
    holdValue = True
    actionString = 'adding hold'
elif removehold:
    holdValue = False
    actionString = 'removing hold'
else:
    print('no action specified')
    exit()

for job in sorted(jobs, key=lambda job: job['name'].lower()):
    if len(jobnames) == 0 or job['name'].lower() in [j.lower() for j in jobnames]:
        print('%s' % job['name'])
        endUsecs = nowUsecs
        while 1:
            runs = api('get', 'protectionRuns?jobId=%s&numRuns=%s&endTimeUsecs=%s&excludeTasks=true' % (job['id'], numruns, endUsecs))
            if len(runs) > 0:
                endUsecs = runs[-1]['backupRun']['stats']['startTimeUsecs'] - 1
            else:
                break
            for run in runs:
                copyRunsFound = False
                for copyRun in run['copyRun']:
                    if 'expiryTimeUsecs' in copyRun and copyRun['expiryTimeUsecs'] > dateToUsecs():
                        copyRunsFound = True
                if copyRunsFound is True:
                    thisRun = api('get', '/backupjobruns?id=%s&exactMatchStartTimeUsecs=%s' % (run['jobId'], run['backupRun']['stats']['startTimeUsecs']))
                    jobUid = {
                        "clusterId": thisRun[0]['backupJobRuns']['protectionRuns'][0]['backupRun']['base']['jobUid']['clusterId'],
                        "clusterIncarnationId": thisRun[0]['backupJobRuns']['protectionRuns'][0]['backupRun']['base']['jobUid']['clusterIncarnationId'],
                        "id": thisRun[0]['backupJobRuns']['protectionRuns'][0]['backupRun']['base']['jobUid']['objectId']
                    }
                    runParams = {
                        "jobRuns": [
                            {
                                "copyRunTargets": [],
                                "runStartTimeUsecs": run['backupRun']['stats']['startTimeUsecs'],
                                "jobUid": jobUid
                            }
                        ]
                    }
                    for copyRun in run['copyRun']:
                        if 'expiryTimeUsecs' in copyRun and copyRun['expiryTimeUsecs'] > dateToUsecs():
                            copyRunTarget = copyRun['target']
                            copyRunTarget['holdForLegalPurpose'] = holdValue
                            runParams['jobRuns'][0]['copyRunTargets'].append(copyRunTarget)
                    # display(runParams)
                    print('    %s - %s' % (usecsToDate(run['backupRun']['stats']['startTimeUsecs']), actionString))
                    result = api('put', 'protectionRuns', runParams)