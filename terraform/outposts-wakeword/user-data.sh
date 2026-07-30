#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 /opt/wakeword
install -d -m 0755 /opt/wakeword/cache
install -d -m 0755 /opt/wakeword/runs
install -d -m 0755 /opt/wakeword/artifacts

# Deep Learning and current Ubuntu/Amazon Linux AMIs normally include SSM
# Agent. Enable whichever installation layout the selected AMI provides.
if systemctl list-unit-files amazon-ssm-agent.service >/dev/null 2>&1; then
  systemctl enable --now amazon-ssm-agent
elif command -v snap >/dev/null 2>&1 &&
     snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap start amazon-ssm-agent
fi

