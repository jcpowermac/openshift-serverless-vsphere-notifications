# openshift-serverless-vsphere-notifications


### slack webhook uri

```
oc create secret generic slack-webhook-uri --from-literal=uri=
```

# TODO: How to create creds.xml
```
  oc create secret generic vcenter-credential --from-file=creds.xml=creds.xml

```
