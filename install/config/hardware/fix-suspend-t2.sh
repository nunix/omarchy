#!/bin/bash

# Load keyboard module on boot
echo apple-bce | sudo tee /etc/modules-load.d/t2.conf

# Service used to fix the touchbar after a suspend
sudo tee /etc/systemd/system/suspend-fix-t2.service <<'EOF'
[Unit]
Description=Disable and Re-Enable Apple BCE Module (and Wi-Fi)
Before=sleep.target
StopWhenUnneeded=yes

[Service]
User=root
Type=oneshot
RemainAfterExit=yes

#ExecStart=/usr/bin/modprobe -r brcmfmac_wcc
#ExecStart=/usr/bin/modprobe -r brcmfmac
ExecStart=/usr/bin/rmmod -f apple-bce

ExecStop=/usr/bin/modprobe apple-bce
#ExecStop=/usr/bin/modprobe brcmfmac
#ExecStop=/usr/bin/modprobe brcmfmac_wcc

[Install]
WantedBy=sleep.target
EOF

sudo systemctl daemon-reload