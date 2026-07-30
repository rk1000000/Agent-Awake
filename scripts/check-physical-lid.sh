#!/bin/bash

set -euo pipefail

lid_state() {
    ioreg -r -n IOPMrootDomain -d 1 \
        | awk -F'= ' '/"AppleClamshellState"/ { print $2; exit }'
}

before_count="$(pmset -g log | grep -c 'Clamshell Sleep' || true)"
deadline=$((SECONDS + 180))
saw_closed=false

echo "READY: закройте крышку на 30 секунд, затем откройте"

while (( SECONDS < deadline )); do
    state="$(lid_state)"
    if [[ "$state" == "Yes" && "$saw_closed" == "false" ]]; then
        saw_closed=true
        echo "LID: closed"
    elif [[ "$state" == "No" && "$saw_closed" == "true" ]]; then
        echo "LID: opened"
        break
    fi
    sleep 1
done

if [[ "$saw_closed" != "true" ]]; then
    echo "FAIL: закрытие крышки не зафиксировано за 180 секунд"
    exit 1
fi

after_count="$(pmset -g log | grep -c 'Clamshell Sleep' || true)"
if (( after_count > before_count )); then
    echo "FAIL: macOS записала новый Clamshell Sleep"
    exit 1
fi

"$(cd "$(dirname "$0")" && pwd)/check-live-protection.sh"
echo "PHYSICAL LID TEST: PASS"
