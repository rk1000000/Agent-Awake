# Contributing to Agent Awake

Thank you for helping improve Agent Awake.

## Before opening a change

1. Search existing issues and discussions.
2. For behavior changes, describe the user-visible result and failure mode first.
3. Keep privileged-helper changes minimal and explain the security boundary they affect.
4. Never commit session logs, credentials, personal paths, app bundles, archives, or build output.

## Local checks

```bash
swift run AgentAwakeTests
swift build -c release -Xswiftc -warnings-as-errors
bash -n AppBundle/install-power-helper.sh scripts/*.sh
```

For changes to closed-lid behavior, also run the physical checks documented in `scripts/check-physical-lid.sh` and `scripts/check-lid-energy.sh` on supported hardware.

## Pull requests

- Use a focused branch and a concise commit message.
- Explain what changed, why, the user impact, and the checks performed.
- Add or update tests for behavior changes.
- Update README or the specification when behavior changes.
- Do not include generated files from `.build`, `dist`, or `work`.

By contributing, you agree that your contribution is licensed under the MIT License.
