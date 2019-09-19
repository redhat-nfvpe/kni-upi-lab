---
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  creationTimestamp: null
  labels:
    machineconfiguration.openshift.io/role: ${role}
  name: ${prio}-${role}-${intf}-dns-priority
spec:
  config:
    ignition:
      config: {}
      security:
        tls: {}
      timeouts: {}
      version: 2.2.0
    networkd: {}
    passwd: {}
    storage: {}
    systemd: {
        "units": [
            {
            "name": "NetworkManager-dns-priority.service",
            "dropins": [{
              "name": "timeout.conf",
              "contents": "[Service]\nExecStart=\nExecStart=/bin/nmcli con mod ${intf} ipv4.dns-priority -1"
            }]
          }
        ]
      }
  osImageURL: ""