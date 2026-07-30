#!/bin/bash

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
    echo "Usage: install-power-helper.sh <helper> <plist> <version>" >&2
    exit 64
fi

helper_source="$1"
plist_source="$2"
version_source="$3"
expected_root="/Applications/Agent Awake.app/Contents"
expected_helper="$expected_root/Library/LaunchServices/com.rodion.agentawake.power-helper"
expected_plist="$expected_root/Resources/com.rodion.agentawake.power-helper.plist"
expected_version="$expected_root/Resources/power-helper.version"
helper_target="/Library/PrivilegedHelperTools/com.rodion.agentawake.power-helper"
plist_target="/Library/LaunchDaemons/com.rodion.agentawake.power-helper.plist"
version_target="/Library/PrivilegedHelperTools/com.rodion.agentawake.power-helper.version"

if [[ "$helper_source" != "$expected_helper" ||
      "$plist_source" != "$expected_plist" ||
      "$version_source" != "$expected_version" ]]; then
    echo "Refusing to install helper from an unexpected path" >&2
    exit 65
fi

for source in "$helper_source" "$plist_source" "$version_source"; do
    if [[ ! -f "$source" || -L "$source" ]]; then
        echo "Refusing a missing, non-regular, or symlinked source: $source" >&2
        exit 66
    fi
done

/bin/launchctl bootout system/com.rodion.agentawake.power-helper >/dev/null 2>&1 || true
for _ in {1..20}; do
    if ! /bin/launchctl print system/com.rodion.agentawake.power-helper >/dev/null 2>&1; then
        break
    fi
    /bin/sleep 0.5
done
/usr/bin/install -o root -g wheel -m 755 "$helper_source" "$helper_target"
/usr/bin/install -o root -g wheel -m 644 "$plist_source" "$plist_target"
/usr/bin/install -o root -g wheel -m 644 "$version_source" "$version_target"
/bin/launchctl bootstrap system "$plist_target"
/bin/launchctl kickstart system/com.rodion.agentawake.power-helper
