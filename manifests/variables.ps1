$ci = @"
{
    "vmc": {
        "vcenter": "vcenter.sddc-44-236-21-251.vmwarevmc.com",
        "datacenter": "SDDC-Datacenter",
        "cluster": "Cluster-1",
        "datastore": "WorkloadDatastore",
        "secret": "/var/run/secret/vcenter/vmc.xml"
    },
    "ibm": {
        "vcenter": "vcs8e-vc.ocp2.dev.cluster.com",
        "datacenter": "IBMCloud",
        "cluster": "vcs-ci-workload",
        "datastore": "vsanDatastore",
        "secret": "/var/run/secret/vcenter/ibm.xml"
    }
}
"@
