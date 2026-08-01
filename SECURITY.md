# Security Policy

## Supported versions

Security fixes are provided for the latest minor version on the default branch.

| Version | Supported |
| --- | --- |
| 0.5.x | Yes |
| 0.4.x | No |
| Earlier versions | No |

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use [GitHub private vulnerability reporting](https://github.com/rk1000000/Agent-Awake/security/advisories/new) and include:

- the affected version and macOS version;
- reproduction steps or a proof of concept;
- the expected and actual security boundary;
- any suggested remediation.

You should receive an acknowledgement within seven days. Please allow time for a fix before public disclosure.

## Security boundaries

Agent Awake is a local macOS utility with no network client, backend, telemetry, updater, or third-party runtime dependency. Its highest-risk component is the administrator-approved power helper. The helper accepts only a small, owner-only heartbeat tied to the installed app's path, PID, and UID, and it restores normal power settings when that heartbeat expires.

Local builds are ad-hoc signed and are not equivalent to a notarized Developer ID release. Review the source and build it locally if your threat model includes software supply-chain attacks.
