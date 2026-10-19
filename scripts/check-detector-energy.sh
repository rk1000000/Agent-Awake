#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/detector-energy
git show HEAD:Sources/AgentAwakeCore/AgentActivityDetector.swift > work/detector-energy/Original.swift
python3 - <<'PY'
from pathlib import Path
s=Path('work/detector-energy/Original.swift').read_text()
s=s[s.index('public final class AgentActivityDetector'):]
Path('work/detector-energy/Before.swift').write_text('import Foundation\n'+s.replace('AgentActivityDetector','BeforeDetector'))
PY
swiftc -O Sources/AgentAwakeCore/AgentActivityDetector.swift Sources/AgentAwakeCore/SessionFileIndex.swift Sources/AgentAwakeCore/AgentLogClassifier.swift work/detector-energy/Before.swift scripts/DetectorEnergyCheck.swift -o work/detector-energy/check
work/detector-energy/check
