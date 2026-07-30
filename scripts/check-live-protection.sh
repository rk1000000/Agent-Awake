#!/bin/bash

set -euo pipefail

app_binary="/Applications/Agent Awake.app/Contents/MacOS/AgentAwake"

if ! pgrep -f "^${app_binary}$" >/dev/null; then
    echo "FAIL: Agent Awake не запущен"
    exit 1
fi

assertions="$(pmset -g assertions)"
if ! grep -q 'Agent Awake:' <<<"$assertions"; then
    echo "FAIL: Agent Awake не держит power assertion"
    exit 1
fi

sleep_disabled="$(ioreg -r -n IOPMrootDomain -d 1 | awk -F'= ' '/"SleepDisabled"/ { print $2; exit }')"
if [[ "$sleep_disabled" != "Yes" ]]; then
    echo "FAIL: системный запрет сна от крышки не включён (SleepDisabled=$sleep_disabled)"
    exit 1
fi

echo "PASS: Agent Awake держит assertion; SleepDisabled=Yes"
