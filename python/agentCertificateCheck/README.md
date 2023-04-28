# Report Agent Certificates using Python

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code is intentionally kept simple to retain value as example code. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

This script will report certificate expirations for registered agents.

Note: this script will only run on Linux where the openssl command is available. You can run it directly on the Cohesity cluster if shell access is available, or on a linux host. The script requires direct network access to the hosts via port 50051/tcp, so inter-site firewall rules would be problematic.

## Components

* agentCertificateCheck.py: the main python script - md5 checksum: d1a24550eef62cc9ca1ac627382ae321
* pyhesity.py: the Cohesity REST API helper module - md5 checksum: 2147a0db6ec080eb3a489b4a0325e0ce

You can download the scripts using the following commands:

```bash
# download commands
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/agentCertificateCheck/agentCertificateCheck.py
curl -O https://raw.githubusercontent.com/bseltz-cohesity/scripts/master/python/pyhesity.py
chmod +x agentCertificateCheck.py
# end download commands
```

## Prerequisites To Run The Script

```bash
chmod +x agentCertificateCheck.py
```

If the 'chmod' prerequsite cannot be run for any reason, please run the script with the precurser 'python3' (or 'python' depending on the version python currently installed on the system) like:

```bash
python3 agentCertificateCheck.py -v mycluster -u myuser -d local
```

To verify the version of python currently installed on the system:

```bash
python --version
```

## Examples

Running the script against one cluster (with direct authentication):

```bash
./agentCertificateCheck.py -v mycluster -u myuser -d local  # -d myAdDomain.net (for active directory)
```

Running the script against all Helios clusters (note: you will need to create an API key in helios and use that as the password when prompted):

```bash
./agentCertificateCheck.py -u myuser@mydomain.net
```

Running the script against selected Helios clusters (note: you will need to create an API key in helios and use that as the password when prompted):

```bash
./agentCertificateCheck.py -u myuser@mydomain.net -c cluster1 -c cluster2
```

## Authentication Parameters

* -v, --vip: (optional) DNS or IP of the Cohesity cluster to connect to (default is helios.cohesity.com)
* -u, --username: (optional) username to authenticate to Cohesity cluster (default is helios)
* -d, --domain: (optional) domain of username (defaults to local)
* -i, --useApiKey: (optional) use API key for authentication
* -pwd, --password: (optional) password or API key
* -np, --noprompt: (optional) do not prompt for password
* -mcm, --mcm: (optional) connect through MCM
* -c, --clustername: (optional) helios/mcm cluster to connect to (will loop through all clusters if connected to helios)
* -m, --mfacode: (optional) MFA code for authentication
* -e, --emailmfacode: (optional) send MFA code via email

## Other Parameters

* -w, --excludewindows: (optional) skip windows sources
* -x, --expirywarningdate: (optional) default is '2023-06-01 00:00:00'

## What Does Unknown Mean

There are several failure modes that can result in a lack of response or lack of details returned for an agent, resulting in 'unknown' in the script output. For example:

* **Agent never successfully registered**: this can happen if the agent was already registered with another cluster when registration was attempted. In this case, the agent will appear unreachable and most of the details will remain unknown.

* **Agent was successfully registered but is now offline**: in this case we will have some of the details from the last time the cluster conversed with the agent, but since it's now offline, it will appear unreachable and the certificate date will remain unknown.

* **Agent is not reachable over the network**: this may be caused by running the script from a jump host that does not have direct access to the agent hosts, likely due to firewall rules or air gapped networks that the jump host can't reach. Running the script directly on the cluster may alleviate some of these issues. It may also be that Hybrid Extender (HyX) is in use and therefore no direct network access is possible. Again, we will successfully retrieve some of the agent details but the agent will appear unreachable and the certificate date will remain unknown.

## The Python Helper Module - pyhesity.py

The helper module provides functions to simplify operations such as authentication, api calls, storing encrypted passwords, and converting date formats. The module requires the requests python module.

### Installing the Prerequisites

```bash
sudo yum install python-requests
```

or

```bash
sudo easy_install requests
```