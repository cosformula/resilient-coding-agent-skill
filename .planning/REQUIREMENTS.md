# Requirements: Resilient Coding Agent Skill

## v1 Requirements

### Table Stakes

| ID | Requirement | Description |
|----|-------------|-------------|
| TS-1 | PID-based crash detection | Track actual Claude Code child PID; use `kill -0` for liveness checks instead of regex heuristics |
| TS-2 | Done-file completion markers | Filesystem-based completion: `$TMPDIR/done` + `$TMPDIR/exit_code` replace `__TASK_DONE__` grep |
| TS-3 | Continuous output capture | `tmux pipe-pane` streams all output to `$TMPDIR/output.log` from session creation |
| TS-4 | ANSI escape stripping | Strip terminal escape sequences inline in the pipe-pane pipeline for clean Brain consumption |
| TS-5 | Model routing | Brain passes `opus` or `sonnet`; skill maps to `--model claude-opus-4-6` or `--model claude-sonnet-4-6` |
| TS-6 | Structured task manifest | `manifest.json` with task_name, model, pid, status, timestamps; machine-readable task state |
| TS-7 | Secure temp directory management | Standardize `mktemp -d` + `chmod 700` directory with canonical file layout |
| TS-8 | File-based prompt delivery | Preserve existing write-to-file pattern; never interpolate prompts into shell commands |
| TS-9 | Claude Code only | Remove all Codex, OpenCode, Pi code paths from SKILL.md and monitor.sh |
| TS-10 | Aggressive scope claiming | SKILL.md claims ALL non-chat tasks; no duration threshold; Brain must delegate everything |

### Differentiators

| ID | Requirement | Description |
|----|-------------|-------------|
| D-1 | Hang detection | Detect agents alive but stuck via output.log mtime staleness as proxy heartbeat |
| D-2 | All tasks via tmux | No fast path; every task gets tmux session + monitor regardless of expected duration |
| D-3 | Rewritten monitor | Three-layer detection: done-file first, then PID liveness, then output staleness |
| D-4 | Task state directory convention | Canonical layout documented: prompt, pid, output.log, manifest.json, done, exit_code |
| D-5 | Atomic manifest updates | Write-to-tmp + `mv` pattern prevents Brain from reading partial JSON |
| D-6 | Configurable monitor intervals | MONITOR_BASE_INTERVAL / MONITOR_MAX_INTERVAL / MONITOR_DEADLINE via env vars |
| D-7 | Retry exhaustion notification | Final manifest update (status: abandoned) + `openclaw system event` when deadline hit |
| D-8 | Output tail for Brain | Last 100 lines of output.log added to manifest.json on completion; `tail -n 50` pattern documented |

## Out of Scope (v2+)

| ID | Requirement | Reason |
|----|-------------|--------|
| AF-1 | SQLite task database | File-based state sufficient for expected concurrency |
| AF-2 | Node.js CLI wrapper | No functional benefit; adds runtime dependency |
| AF-3 | Named pipes / Unix sockets | File polling sufficient; real-time streaming not required |
| AF-4 | Multi-agent support | Muscles uses Claude Code exclusively |
| AF-5 | Reboot resilience | Manual recovery acceptable; adds significant complexity |
| AF-6 | Generic orchestrator support | OpenClaw-specific; no second orchestrator exists |
| AF-7 | Interactive approval workflows | Breaks fire-and-forget model |
| AF-8 | Output streaming to Brain | File polling sufficient; sub-second latency not required |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TS-1 | Phase 2 | Complete |
| TS-2 | Phase 2 | Complete |
| TS-3 | Phase 2 | Complete |
| TS-4 | Phase 2 | Complete |
| TS-5 | Phase 1 | Complete |
| TS-6 | Phase 3 | Complete |
| TS-7 | Phase 1 | Complete |
| TS-8 | Phase 1 | Complete |
| TS-9 | Phase 1 | Complete |
| TS-10 | Phase 1 | Complete |
| D-1 | Phase 4 | Pending |
| D-2 | Phase 5 | Pending |
| D-3 | Phase 4 | Pending |
| D-4 | Phase 1 | Complete |
| D-5 | Phase 3 | Complete |
| D-6 | Phase 4 | Pending |
| D-7 | Phase 4 | Pending |
| D-8 | Phase 3 | Complete |
