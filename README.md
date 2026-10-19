# Agent Awake

**Keep long-running Claude Code and OpenAI Codex tasks alive on macOS — even with the lid closed — then let your Mac sleep when the work is done.**

[![CI](https://github.com/rk1000000/Agent-Awake/actions/workflows/ci.yml/badge.svg)](https://github.com/rk1000000/Agent-Awake/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 6.1](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://www.swift.org/)

Agent Awake is a native, local-only macOS menu bar app for unattended AI coding sessions. It combines a normal idle-sleep assertion with a small privileged helper for clamshell sleep, watches local Claude Code and Codex session logs, and automatically releases the Mac when the selected timer or agent work finishes.

> [!WARNING]
> A closed MacBook still produces heat. Never run it inside a bag, drawer, or on a soft surface. Agent Awake can optionally stop the session when macOS reports a dangerous thermal state, but software is not a substitute for ventilation.

## Why Agent Awake?

`caffeinate` can prevent ordinary idle sleep, but closing a MacBook lid follows a separate clamshell-sleep path. General keep-awake apps can cover timers, yet AI coding sessions need a different lifecycle: stay awake only while Claude Code or Codex is actively working, then release the machine automatically.

Agent Awake is designed for that exact workflow:

- **Agent-aware mode** — detects active Claude Code, Codex CLI, and Codex Desktop tasks from local session state.
- **Closed-lid operation** — maintains the system sleep override only while a fresh, authenticated local heartbeat exists.
- **Timers** — 30 minutes, 1 hour, 2 hours, indefinite, or any custom value from 1–60 minutes.
- **Automatic release** — allow normal macOS sleep or request immediate sleep after agents finish.
- **Energy saving** — after 10 seconds with the lid closed, optionally set the built-in display to 0% and enable Low Power Mode.
- **Thermal safety** — optionally release all holds and sleep when macOS reports `serious` or `critical` thermal pressure.
- **Clear feedback** — menu bar countdown, a one-time Funk warning in the last timer minute, plus separate Purr and Tink sounds for sleep protection and completed energy saving.
- **Charging diagnostics** — compares adapter wattage with the Apple-recommended baseline for supported Mac models, shows current Mac input and a confirmed cable/connection lower bound, and warns about sustained weak power.
- **Private by design** — no network requests, accounts, analytics, telemetry, or cloud service.

## Requirements

- macOS 14 or newer.
- Apple Silicon is tested; Intel Macs are not currently validated.
- Swift 6.0 or newer and the Xcode Command Line Tools for building from source.
- Installation in `/Applications/Agent Awake.app` for the privileged helper and launch-at-login support.

The current implementation has been tested on a 2021 MacBook Pro with Apple M1 Pro. Compatibility with future Claude Code, Codex, or macOS log formats is not guaranteed.

Built-in display brightness automation uses Apple's private DisplayServices framework. Agent Awake handles an unavailable framework as an error, but that feature may require maintenance after macOS updates.

Charging diagnostics use the power values that macOS exposes locally. macOS reports the connected adapter wattage and, on supported Apple Silicon models, live power telemetry. For `MacBookPro18,1` and `MacBookPro18,2`, Agent Awake compares the adapter with Apple's 140 W recommendation for the 16-inch 2021 MacBook Pro. It does not provide a stable public field for the cable's printed 60/100/240 W rating, so Agent Awake shows only the minimum wattage demonstrably passing through the connection and labels an unavailable rating as unknown. An adapter below the recommendation is a useful compatibility signal, but it is not treated as proof of a charging fault unless macOS reports slow charging or the battery is actually discharging on external power.

## Build and install from source

```bash
git clone https://github.com/rk1000000/Agent-Awake.git
cd Agent-Awake
./scripts/build-app.sh
ditto "dist/Agent Awake.app" "/Applications/Agent Awake.app"
open "/Applications/Agent Awake.app"
```

The build is ad-hoc signed for local use, not notarized for public binary distribution. The first time closed-lid protection is needed, macOS asks for administrator approval to install the minimal power helper. The helper can only be installed from the expected application path.

## Recommended setup for AI coding agents

1. Choose **While agents are working** (`Пока работают агенты`).
2. Keep **Work with lid closed** enabled.
3. Keep **Allow normal sleep after agents finish** enabled.
4. Enable thermal protection if the Mac may remain unattended.
5. Close any active Amphetamine session to avoid competing sleep assertions.

The current UI is in Russian. English localization is welcome.

## How detection works

Agent Awake reads only local state transitions from recent JSONL session files:

- Codex: `task_started` and `task_complete`.
- Claude Code: user turn start and `end_turn`/stop completion.

Prompt and response text is never stored, uploaded, or displayed. Files older than 30 minutes without a completion event are ignored so abandoned sessions cannot hold the Mac indefinitely.

## Security model

Closed-lid protection requires a root-owned helper because macOS clamshell sleep is outside the normal app sandbox. The helper:

- has no network access;
- only invokes fixed `pmset` settings;
- accepts a heartbeat no larger than 4 KB;
- rejects symlinks and files with permissions other than `0600`;
- verifies the file owner, heartbeat UID, process UID, executable path, and freshness;
- restores normal sleep after a stale heartbeat or application exit.

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities and the supported-version policy.

## Development

Power helper version 6 releases temporary Foundation objects after every polling
iteration. This fixes autoreleased-object accumulation without changing
sleep, heartbeat validation, or low-power behaviour. Updating an existing installation
requires replacing both its bundled helper/version and the installed privileged helper;
the menu-bar executable can remain unchanged.

```bash
swift run AgentAwakeTests
swift build -c release -Xswiftc -warnings-as-errors
swift scripts/check-helper-memory.swift "$PWD"
bash -n AppBundle/install-power-helper.sh scripts/*.sh
```

The package has no third-party runtime dependencies. See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## FAQ

### Can Agent Awake keep a MacBook awake with the lid closed?

Yes. During an active session, Agent Awake combines a normal power assertion with a privileged helper that maintains the macOS `SleepDisabled` setting. It automatically removes the override when the session ends or its heartbeat becomes stale.

### Is Agent Awake an Amphetamine or caffeinate alternative?

It overlaps with their keep-awake use case, but focuses on Claude Code and Codex automation. Agent Awake can detect when supported AI coding agents finish and release the Mac without a manually estimated timer.

### Does Agent Awake send Claude Code or Codex data anywhere?

No. Agent Awake has no networking code or telemetry. Agent state is derived locally, and conversation content is neither stored nor transmitted by the app.

### Will it prevent overheating?

No software can guarantee that. Optional thermal protection reacts to the official macOS thermal state, but users must still provide airflow and avoid enclosed spaces.

### Can Agent Awake tell whether my charger or cable is too weak?

It can identify a sustained power shortfall: macOS reports a slow charger, or the battery continues discharging by more than 1 W while external power is connected. The menu then suggests checking the adapter or cable and plays Sosumi once after 10 seconds. Compatible higher- or lower-wattage USB-C Power Delivery adapters are safe to use; lower available power can charge more slowly or fail to keep up with a heavy workload. Because macOS does not reliably expose the cable's physical rating, Agent Awake never invents one or claims which component is at fault.

### Why is administrator approval required?

Ordinary applications can block idle sleep but cannot reliably override clamshell sleep. The administrator-approved helper performs only the required fixed power-setting operations and continuously requires a verified application heartbeat.

## License

Agent Awake is available under the [MIT License](LICENSE).

### Detector polling cost

Session discovery caches directory entries using fresh filesystem metadata.
Each two-second poll still checks every journal's current metadata and session age,
but unchanged journals reuse their last activity result instead of parsing JSON again.
A changed, replaced, truncated or expired journal is re-evaluated on the next poll.
`bash scripts/check-detector-energy.sh` compares the detector with the original
implementation on copies of 50 real local sessions and measures warm polling time.
It requires this repository's original detector in HEAD and local Claude/Codex logs.
