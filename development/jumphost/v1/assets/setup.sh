#!/bin/bash
echo "AllowAgentForwarding no"    >> /etc/ssh/sshd_config
echo "PermitTTY no"               >> /etc/ssh/sshd_config
echo "ForceCommand echo Jumphost" >> /etc/ssh/sshd_config
systemctl restart sshd