# openshift-serverless-vsphere-notifications

I first started with making this serverless but this is significantly easier.

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

### Create cronjob

Modify the environmental variable for your vCenter url, then apply

```
oc apply -f manifests/cronjob.yaml
```

