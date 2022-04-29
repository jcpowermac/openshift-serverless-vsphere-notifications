#!/usr/bin/pwsh

$image = "quay.io/jcallen/vsphere-slack-notify:latest"
$namespace = "vsphere-alerts"

$schedule = "0 0 */3 * *"

$hostalias = @"
          hostAliases:
          - hostnames:
            - vcs8e-vc.ocp2.dev.cluster.com
            ip: 192.168.133.73
"@

$cronjob = @"
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {0}
  namespace: $($namespace)
spec:
  concurrencyPolicy: Forbid
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: Never
          containers:
          - args:
            - /bin/pwsh
            - -File
            - /projects/{1}
            env:
            - name: SLACK_WEBHOOK_URI
              valueFrom:
                secretKeyRef:
                  key: uri
                  name: slack-webhook-uri
            image: $($image)
            imagePullPolicy: Always
            name: powershell-scripts
            volumeMounts:
            - mountPath: /var/run/secret/vcenter
              name: vcenter-credentials
              readOnly: true
            - mountPath: /var/run/config/vcenter
              name: vcenter-configs
              readOnly: true
$($hostalias)
          volumes:
          - name: vcenter-credentials
            secret:
              defaultMode: 420
              secretName: vcenter-credentials
          - name: vcenter-configs
            configMap:
              name: vcenter-configs
  schedule: $($schedule)
  successfulJobsHistoryLimit: 1
"@

Get-ChildItem -File -Path ./scripts | %{
    $metadataName = ($_.Name -split '\.')[0]
    $cronjob -f $metadataName, $_.Name | Out-File -Force -FilePath ./manifests/"$($metadataName)".yaml
}

#oc create configmap vcenter-configs --dry-run=client --from-file=manifests/variables.ps1 -o yaml
#oc create secret generic vcenter-credentials --from-file=ibm.xml=./secrets/ibm.xml --from-file=vmc.xml=./secrets/vmc.xml
