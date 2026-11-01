# Desktop contracts

`Sources/ShowbackCore/Desktop.swift` owns window selection, desktop sessions, current target lookup, actions, and expected-state waits. `Process.swift` owns bounded subprocess delivery; it passes argument arrays without a shell and preserves the launching environment.

- Use agent-desktop's public commands; never read its caches or private renderer protocol.
- Start an isolated session before observing the desktop. A global host can retain stale display inventory.
- Match the exact application name and, when supplied, exact window title. Refuse ambiguous or missing windows and action targets.
- Resolve fresh refs per action. Respect delivery errors; never repeat a possibly delivered action automatically.
- Conditions pass on a direct match. Exclude container matches caused only by a matching descendant.
- UI readiness uses bounded condition polling. Pointer travel is presentation pacing, not a substitute for readiness.
- Close the session even on failure or cancellation. A process lock prevents concurrent Showback demos.

Relevant checks: `DesktopTests`, `ProcessTests`, `RunLockTests`, `scripts/check-cli.py`, and controlled fixture runs.
