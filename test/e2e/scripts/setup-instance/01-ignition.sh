#!/usr/bin/env bash

printf '=%.0s' {0..79} ; echo
set -ex

cd "$(dirname $0)"
ssh-keygen -b 4096 -t rsa -C "datadog" -N "" -f "id_rsa"
SSH_RSA=$(cat id_rsa.pub)
KUBE_VERSION=${KUBE_VERSION:-"latest}

tee ignition.json << EOF
{
  "passwd": {
    "users": [
      {
        "sshAuthorizedKeys": [
          "${SSH_RSA}"
        ],
        "name": "core"
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "mask": true,
        "name": "user-configdrive.service"
      },
      {
        "mask": true,
        "name": "user-configvirtfs.service"
      },
      {
        "mask": true,
        "name": "locksmithd.service"
      },
      {
        "enabled": true,
        "name": "oem-cloudinit.service",
        "contents": "[Unit]\nDescription=Cloudinit from platform metadata\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/coreos-cloudinit --oem=ec2-compat\n\n[Install]\nWantedBy=multi-user.target\n"
      },
      {
        "enabled": true,
        "name": "setup-pupernetes.service",
        "contents": "[Unit]\nDescription=Setup pupernetes\n\n[Service]\nType=oneshot\nExecStart=/opt/bin/setup-pupernetes\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\n"
      },
      {
        "enabled": true,
        "name": "pupernetes.service",
        "contents": "[Unit]\nDescription=Run pupernetes\nRequires=setup-pupernetes.service docker.service\nAfter=setup-pupernetes.service docker.service\n\n[Service]\nEnvironment=SUDO_USER=core\nExecStart=/opt/bin/pupernetes daemon run /opt/sandbox --kubectl-link /opt/bin/kubectl -v 5 --hyperkube-version ${KUBE_VERSION} --run-timeout 48h\nRestart=on-failure\nRestartSec=5\nType=notify\n\n[Install]\nWantedBy=multi-user.target\n"
      },
      {
        "name": "terminate.service",
        "contents": "[Unit]\nDescription=Trigger a poweroff\n\n[Service]\nExecStart=/bin/systemctl poweroff\nRestart=no\n"
      },
      {
        "enabled": true,
        "name": "terminate.timer",
        "contents": "[Timer]\nOnBootSec=7200\n\n[Install]\nWantedBy=multi-user.target\n"
      }
    ]
  },
  "storage": {
    "files": [
      {
        "path": "/etc/coreos/update.conf",
        "mode": 420,
        "contents": {
          "source": "data:,GROUP%3Dalpha%0AREBOOT_STRATEGY%3Doff%0A"
        },
        "filesystem": "root"
      },
      {
        "path": "/opt/bin/setup-pupernetes",
        "mode": 320,
        "contents": {
          "source": "data:,%23%21%2Fbin%2Fbash%20-ex%0Acurl%20-Lf%20https%3A%2F%2Fgithub.com%2FDataDog%2Fpupernetes%2Freleases%2Fdownload%2Fv0.10.0%2Fpupernetes%20-o%20%2Fopt%2Fbin%2Fpupernetes%0Asha512sum%20-c%20%2Fopt%2Fbin%2Fpupernetes.sha512sum%0Achmod%20%2Bx%20%2Fopt%2Fbin%2Fpupernetes%0A"
        },
        "filesystem": "root"
      },
      {
        "path": "/opt/bin/pupernetes.sha512sum",
        "mode": 256,
        "contents": {
          "source": "data:,35353ea46464a9c77848fbc03745de8fc6bf90b7e0ecf8011f48973b6cba571e8d3964e995397d8a8ba368d0f127b82deaa2ff916ca7544fba1b44dc6ee94bf5%20%2Fopt%2Fbin%2Fpupernetes%0A"
        },
        "filesystem": "root"
      }
    ]
  },
  "ignition": {
    "version": "2.1.0"
  }
}
EOF
