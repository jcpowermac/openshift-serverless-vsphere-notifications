# openshift-serverless-vsphere-notifications

I first started with making this serverless but this is significantly easier.

## Overview

This project provides automated monitoring and alerting for VMware vSphere environments through OpenShift CronJobs. It includes:

- **ESXi Health Alerts**: Monitors hardware sensors and health status of ESXi hosts
- **vCenter Alarms**: Monitors vCenter-triggered alarms, system health, and storage health
- **Additional Monitoring**: Resource pools, CNS volumes, orphaned VMs, and more

## Setup

### Create secrets

Grab a incoming webhook uri from Slack and create the secret
```
oc create secret generic slack-webhook-uri --from-literal=uri=<uri-here>
```

Create a vCenter auth secret

```
Get-Credential | Export-Clixml creds.xml
oc create secret generic vcenter-credential --from-file=creds.xml=creds.xml
```

### Create cronjobs

Modify the environmental variable for your vCenter url, then apply

```
oc apply -f manifests/esxialerts.yaml
oc apply -f manifests/vcenteralarms.yaml
```

## Monitoring Capabilities

### ESXi Health Alerts (`esxialerts`)
- Monitors hardware sensor health (temperature, power, etc.)
- Runs every 5 minutes
- Reports any sensors in non-green health state

### vCenter Alarms (`vcenteralarms`)
- Monitors triggered alarm states from datacenter level
- Checks active alarms with non-green status
- Monitors vCenter system health (general and storage)
- Identifies system-critical alarms
- Runs every 5 minutes
- Provides detailed alarm information including entity names and descriptions

### Additional Scripts
- **Resource Pools**: Monitor resource pool usage
- **CNS Volumes**: Track CNS volume counts
- **Orphaned VMs**: Identify VMs without proper resource pools
- **Storage Policies**: Monitor SPBM storage policies
- **Folder Tags**: Track folder and tag usage

## Configuration

The system uses a JSON configuration file (`manifests/variables.ps1`) to define vCenter connections:

```json
{
    "vmc": {
        "vcenter": "vcenter.sddc-44-236-21-251.vmwarevmc.com",
        "datacenter": "SDDC-Datacenter",
        "cluster": "Cluster-1",
        "datastore": "WorkloadDatastore",
        "secret": "/var/run/secret/vcenter/vmc.xml"
    }
}
```

## Testing

Use the test script to verify connectivity and functionality:

```bash
oc exec -it <pod-name> -- pwsh -File /projects/test-vcenteralarms.ps1
```

## Dependencies

- **Base Image**: Microsoft .NET SDK 9.0 (Debian-based) - includes PowerShell 7.x
- **VMware PowerCLI**: For vSphere management
- **PSSlack module**: For Slack notifications
- **VMware vSphere SSO Admin module**: For CIS API access
- **Package Manager**: apt (Debian) instead of dnf (RHEL)

## Image Details

The project now uses Debian-based images instead of RHEL:
- **Production**: `mcr.microsoft.com/dotnet/sdk:9.0` (includes PowerShell)
- **Development**: `mcr.microsoft.com/dotnet/sdk:9.0` (includes PowerShell)

