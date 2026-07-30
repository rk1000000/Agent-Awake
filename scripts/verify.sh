#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_binary="$project_dir/dist/Agent Awake.app/Contents/MacOS/AgentAwake"

cd "$project_dir"
swift run AgentAwakeTests

if [[ ! -x "$app_binary" ]]; then
    echo "BLOCKED: приложение не собрано"
    exit 1
fi

diagnostic_output="$("$app_binary" --diagnostics)"
echo "$diagnostic_output"

if ! grep -q '^Result: PASS$' <<<"$diagnostic_output"; then
    echo "BLOCKED: системная диагностика не прошла"
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$project_dir/dist/Agent Awake.app"
"$project_dir/scripts/check-live-protection.sh"
if ! launchctl print "gui/$(id -u)/com.rodion.agentawake.login" >/dev/null 2>&1; then
    echo "BLOCKED: автозапуск Agent Awake не зарегистрирован"
    exit 1
fi
echo "Launch at login: OK"
echo "VERIFY: PASS"
