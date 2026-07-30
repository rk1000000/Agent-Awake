#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
dist_dir="$project_dir/dist"
app_dir="$dist_dir/Agent Awake.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
launch_services_dir="$contents_dir/Library/LaunchServices"

cd "$project_dir"
swift run AgentAwakeTests
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir" "$launch_services_dir"

cp "$bin_dir/AgentAwake" "$macos_dir/AgentAwake"
cp "$bin_dir/AgentAwakePowerHelper" "$launch_services_dir/com.rodion.agentawake.power-helper"
cp "$project_dir/AppBundle/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/README.md" "$resources_dir/README.md"
cp "$project_dir/spec/SPEC.md" "$resources_dir/SPEC.md"
cp "$project_dir/AppBundle/com.rodion.agentawake.power-helper.plist" "$resources_dir/com.rodion.agentawake.power-helper.plist"
cp "$project_dir/AppBundle/power-helper.version" "$resources_dir/power-helper.version"
cp "$project_dir/AppBundle/install-power-helper.sh" "$resources_dir/install-power-helper.sh"
chmod +x "$resources_dir/install-power-helper.sh"

codesign --force --deep --sign - "$app_dir"

rm -f "$dist_dir/Agent-Awake-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$dist_dir/Agent-Awake-macOS.zip"

codesign --verify --deep --strict --verbose=2 "$app_dir"
spctl --assess --type execute --verbose=2 "$app_dir" || true

echo "$app_dir"
echo "$dist_dir/Agent-Awake-macOS.zip"
