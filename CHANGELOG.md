# Changelog

## 0.5.2 (22) — 2026-10-24

- **Feature:** "Своё время…" takes hours and minutes (two fields), from 1 minute to 24 hours; it was 1–60 minutes.
  The menu bar shows the remaining time over an hour as `2h 05m`.

## 0.5.1 (21) — 2026-10-24

- **Fix:** the Mac could stay unable to sleep forever (even with Agent Awake quit) after a reboot or crash during a
  closed-lid session. `pmset disablesleep` survives a reboot, but the helper kept its ownership marker in `/var/run`,
  which is wiped at boot. Helper version 7 keeps markers in `/Library/Application Support/com.rodion.agentawake/` and
  releases a leftover `SleepDisabled` flag at start. Verified live: stuck flag 1 → 0 on install; normal quit → 0;
  crash (`kill -9`) → 0 after 1 s.
- **Fix:** "Put Mac to sleep after agents" waits until the helper clears `SleepDisabled` before `pmset sleepnow`.
- **Perf:** CPU of the menu-bar app — Off mode 8 % → 0.7 % of one core; agents mode 6.2 % → 2.45 %.
  Journals are scanned every 30 s outside agents mode; grown journals are read from where the previous poll stopped,
  with a full re-read at least once a minute.
- Review: Codex GPT-6.1 Sol medium, rounds 1–3 Fail (detector rewrite cases, fixed), round 4 Pass
  (`review/codex-review-2026-10-24-sleep-stuck-round4.md`, kept outside git).
- Rollback: `work/backups/Agent Awake 0.5.0 build-20 before-sleep-fix.app` and helper version 6.
