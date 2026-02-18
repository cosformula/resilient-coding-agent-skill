# Resilient Coding Agent — Rewrite

## What This Is

The "Muscles" layer for OpenClaw. The Brain (Codex 5.3) handles chat, routing, and memory with minimal tokens. This skill handles everything else — all coding, reasoning, debugging, refactoring, file exploration, and analysis work — by delegating to Claude Code sessions running in tmux. This architecture exists because Anthropic no longer permits OAuth-based API sessions for coding work; Claude Code CLI sessions are the compliant path.

## Core Value

Every coding task the Brain delegates must reliably execute in an isolated Claude Code session, with the right model for the job, crash recovery, output capture, and structured results — regardless of what happens to the orchestrator process.

## Requirements

### Validated

<!-- Existing capabilities confirmed working in current codebase -->

- ✓ tmux session creation decouples agent from orchestrator lifecycle — existing
- ✓ Secure temp directories via `mktemp -d` with `chmod 700` — existing
- ✓ File-based prompt delivery prevents shell injection — existing
- ✓ Session name sanitization (`[A-Za-z0-9._-]+`) — existing
- ✓ Health monitoring polling loop with exponential backoff — existing
- ✓ Auto-resume via `claude --resume` after crash detection — existing
- ✓ 5-hour wall-clock deadline prevents infinite monitoring — existing
- ✓ `openclaw system event` callback for completion notification — existing
- ✓ ClawHub publishing pipeline (CI + GitHub Actions) — existing

### Active

<!-- Rewrite scope -->

- [ ] Claude Code only — remove Codex, OpenCode, Pi support entirely
- [ ] Model routing — Brain passes `<model>` parameter (opus or sonnet); skill launches Claude Code with the specified model
- [ ] Aggressive scope claiming in SKILL.md — "When to Use" becomes "always, for any non-chat task" to prevent Brain from trying to code itself
- [ ] All tasks via tmux — even quick lookups get a session (no duration threshold)
- [ ] PID-based crash detection — replace regex prompt matching with process existence checks via `kill -0`
- [ ] Done-file completion markers — replace `__TASK_DONE__` grep with filesystem-based detection (`$TMPDIR/done` + `$TMPDIR/exit_code`)
- [ ] Continuous output capture via `tmux pipe-pane` — persistent log file survives scrollback limits
- [ ] ANSI escape stripping on captured output — clean text for orchestrator consumption
- [ ] Structured task manifest (JSON) — machine-readable task metadata for orchestrator queries
- [ ] Heartbeat file for hang detection — detect agents that are alive but stuck
- [ ] Standardized task directory — persistent state that survives orchestrator restarts
- [ ] Rewritten monitor.sh — PID/done-file/heartbeat detection replacing regex heuristics
- [ ] Simplified SKILL.md — single-agent, model-aware, aggressive scope claiming

### Out of Scope

- Multi-agent support (Codex, OpenCode, Pi) — Muscles uses Claude Code exclusively
- Node.js CLI wrapper — evaluate during planning; not committed
- SQLite task database — file-based state sufficient for expected concurrency
- Named pipes / Unix sockets — file-based approach more resilient to monitor restarts
- Reboot resilience beyond `claude --resume` — tmux lost on reboot; accepted limitation
- Generic orchestrator support — OpenClaw-specific
- Brain logic / routing intelligence — Brain decides what to delegate; this skill just executes

## Context

**Brain / Muscles split:** OpenClaw's Brain (Codex 5.3) is a lightweight coordinator — chat, routing, memory, quick decisions. The Muscles (this skill) handle all substantive work: coding, debugging, refactoring, architecture, file exploration, analysis, tests, docs. The Brain picks the right model tier and hands off via this skill.

**Model tiers (Brain decides, skill executes):**
- **Opus 4.6** — Complex multi-step reasoning, architectural decisions, subtle debugging, security analysis, ambiguous requirements, high-stakes tasks
- **Sonnet 4.6** — Standard feature implementation, tests, code generation, moderate refactoring, API work, file exploration, searches, lookups, formatting, any task where speed matters more than depth

**Why aggressive scope claiming:** AI models naturally try to handle tasks themselves. Codex 5.3 as Brain will have bias toward doing coding work directly. SKILL.md must make it unambiguous: "You are NOT a coding agent. Delegate ALL coding/reasoning work through this skill." The skill doc is the orchestrator's instructions — it needs to be authoritative.

**OpenClaw integration model:** OpenClaw reads SKILL.md as instructions, fills in `<placeholder>` tokens from context, and executes bash commands. Document-driven skill system. Published via ClawHub; SKILL.md is the required artifact.

**Current pain points being fixed:**
- Crash detection uses fragile regex matching on tmux scrollback (false positives/negatives)
- No persistent output capture — results lost when tmux session ends
- No structured task state — orchestrator must remember temp directory paths
- Multi-agent branching adds complexity for a single-agent use case
- No hang detection — stuck agent looks healthy to monitor
- "When to use" threshold too narrow (was "5+ minutes" — should be "always")
- No model selection — all tasks use default model

**Research findings:** PID tracking + done-file markers eliminate crash detection false positives. `tmux pipe-pane` provides continuous output capture. JSON task manifests enable structured queries. Heartbeat files detect hung agents.

## Constraints

- **Distribution:** Published via ClawHub as SKILL.md + optional scripts; must pass CI publish checks
- **Platform:** macOS and Linux (tmux required; no Windows native)
- **Dependencies:** Only tmux and Claude Code CLI (`claude`); no additional runtime required
- **Security:** Prompt delivery must remain file-based (no shell interpolation); temp dirs must use `mktemp -d` + `chmod 700`
- **Interface:** SKILL.md is the orchestrator interface — OpenClaw reads it and follows instructions
- **Scope boundary:** Skill executes tasks; Brain decides what to delegate and which model to use

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Claude Code only | Muscles exclusively uses Claude Code; multi-agent support adds complexity for no benefit | — Pending |
| Brain decides model, skill executes | Brain has task context to judge complexity; skill just takes `<model>` parameter | — Pending |
| Aggressive scope claiming | Prevent Brain bias toward handling coding work itself; SKILL.md must be authoritative | — Pending |
| All tasks via tmux | Even quick tasks get sessions; eliminates duration-based routing complexity | — Pending |
| PID + done-file over regex | Regex crash detection has known false positive/negative issues; PID existence is deterministic | — Pending |
| `tmux pipe-pane` for output | Continuous streaming beats snapshot-based capture; survives scrollback limits | — Pending |
| File-based task state over DB | SQLite overkill for expected concurrency; files simpler and more resilient | — Pending |
| Bash for monitor.sh | tmux interaction is shell-native; Node.js would just wrap child_process.execSync | — Pending |

---
*Last updated: 2026-02-18 after initialization*
