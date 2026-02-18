# Architecture

**Analysis Date:** 2026-02-18

## Pattern Overview

**Overall:** Task Decoupling & Health Monitoring via Process Isolation

**Key Characteristics:**
- Process isolation using tmux to decouple long-running coding agents from the orchestrator lifecycle
- Periodic health monitoring with crash detection and automatic resume capability
- Agent-agnostic framework supporting multiple coding agent CLIs (Codex, Claude Code, OpenCode, Pi)
- Secure temp directory patterns for task state isolation and secret containment
- Shell command injection prevention through file-based prompt delivery and output redirection

## Layers

**Orchestrator Integration Layer:**
- Purpose: Interface point where long-running coding tasks are initiated
- Location: `SKILL.md` (specification for orchestrator implementations)
- Contains: Task startup patterns, environment variable setup, completion notification patterns
- Depends on: Orchestrator's file write tool, tmux availability, coding agent CLIs
- Used by: External orchestrators implementing this skill

**Tmux Session Management Layer:**
- Purpose: Establish and maintain isolated process context for coding agent execution
- Location: `scripts/monitor.sh` (implementation), `SKILL.md` (usage documentation)
- Contains: Session naming conventions, environment variable passing, process spawning commands
- Depends on: tmux binary, shell capabilities (bash/zsh/fish)
- Used by: Orchestrator startup routines, health monitoring loop

**Health Monitoring & Recovery Layer:**
- Purpose: Detect agent crashes, collect state from tmux scrollback, trigger recovery
- Location: `scripts/monitor.sh` (lines 41-121)
- Contains: Session existence checking, output capture and analysis, crash detection logic, resume command dispatch
- Depends on: tmux session state, shell prompt detection heuristics, agent-specific resume APIs
- Used by: Background monitoring cron/timer, crash recovery procedures

**Task State Management Layer:**
- Purpose: Persist task metadata and session identifiers across monitor invocations
- Location: Temporary directories created with `mktemp -d`
- Contains: Prompt files (`$TMPDIR/prompt`), event logs (`$TMPDIR/events.jsonl`), session IDs (`$TMPDIR/codex-session-id`), completion markers (`$TMPDIR/done`)
- Depends on: Filesystem permissions (700 mode for temp dirs), orchestrator write tool
- Used by: Startup routines (write prompt), monitor script (read session ID), task completion detection

**Agent-Specific Adapter Layer:**
- Purpose: Abstract agent-specific behavior (resume commands, session tracking, output format)
- Location: `scripts/monitor.sh` (lines 25-27, 83-111)
- Contains: Agent type validation (codex|claude|opencode|pi), agent-specific resume logic branching
- Depends on: Agent CLI binary availability and API stability
- Used by: Health monitor recovery paths

## Data Flow

**Task Startup:**

1. Orchestrator calls write tool to store prompt in `$TMPDIR/prompt` (no shell involvement)
2. Orchestrator creates new tmux session with `-e "TASK_TMPDIR=$TMPDIR"` to pass temp directory path
3. Orchestrator sends shell command via `tmux send-keys` that:
   - Changes to project directory
   - Reads prompt from file: `"$(cat $TASK_TMPDIR/prompt)"`
   - Invokes agent CLI with that prompt
   - Redirects output to files: `tee $TASK_TMPDIR/events.jsonl`
   - Appends completion marker: `&& echo "__TASK_DONE__"`
4. For Codex, orchestrator polls `events.jsonl` for `thread_id` and saves to `$TMPDIR/codex-session-id`

**Health Monitoring Loop:**

1. Monitor script runs on periodic timer (every 3-5 minutes via cron/background scheduler)
2. Check session existence: `tmux has-session -t "$SESSION"`
3. If session exists, capture recent output: `tmux capture-pane -t "$SESSION" -p -S -120`
4. Analyze last 40 lines for completion marker or crash indicators
5. If crash detected (shell prompt return OR exit indicators):
   - Increment retry counter and double backoff interval
   - Dispatch agent-specific resume command
   - For Codex: read session ID from file, run `codex exec resume <ID>`
   - For Claude: run `claude --resume`
   - For OpenCode: run `opencode run "Continue"`
   - For Pi: stop monitoring (no resume available)
6. If task completed normally (found `__TASK_DONE__` marker), exit monitor
7. If session disappeared, exit monitor
8. Sleep for `180 * (2 ** RETRY_COUNT)` seconds, capped by 5-hour deadline

**State Management:**

- Prompt stored in file to prevent shell injection: reads are literal, no variable expansion
- Event logs accumulated during execution so monitor can inspect output without attaching
- Session IDs extracted during task runtime and persisted for recovery without `resume --last` ambiguity
- Completion markers allow monitor to distinguish normal completion from crash-induced prompt return

## Key Abstractions

**Resilient Task Container:**
- Purpose: Encapsulate a long-running coding task with isolation, monitoring, and recovery
- Examples: `codex-refactor-auth`, `claude-review-pr-42`, `opencode-analyze-perf`
- Pattern: Named tmux session + secure temp directory + health monitor instance

**Crash Detection Strategy:**
- Purpose: Identify when coding agent has crashed or exited abnormally
- Examples: Last line matches shell prompt pattern (`user@host$ `, `% `, `> `), recent output contains exit indicators
- Pattern: Heuristic-based analysis of recent scrollback instead of polling agent status API

**Agent Resume Pattern:**
- Purpose: Recover task execution from known state without losing prior work
- Examples: `codex exec resume <thread-id>`, `claude --resume`, `opencode run "Continue"`
- Pattern: Agent-specific resume API invoked in same tmux session where agent was running

**Secure Prompt Delivery:**
- Purpose: Pass user instructions to agent without shell injection risks
- Examples: Write prompt to `$TMPDIR/prompt`, invoke agent with `"$(cat $TMPDIR/prompt)"`
- Pattern: File-based prompt read prevents variable expansion and quote escaping vulnerabilities

## Entry Points

**For Orchestrators - Task Startup:**
- Location: `SKILL.md` (sections "Start a Task")
- Triggers: Orchestrator receives long-running coding task request (expected > 5 minutes)
- Responsibilities: Create temp directory, write prompt to file, spawn tmux session, save session ID for Codex tasks

**For Orchestrators - Progress Monitoring:**
- Location: `SKILL.md` (section "Monitor Progress")
- Triggers: User requests status update or proactive milestone reporting needed
- Responsibilities: Run `tmux capture-pane` to retrieve agent output without attaching

**For Background Scheduler - Health Monitoring:**
- Location: `scripts/monitor.sh` entry point (lines 21-28)
- Triggers: Periodic timer (every 3-5 minutes), typically via cron or orchestrator background task
- Responsibilities: Check session health, detect crashes, dispatch recovery commands

**Manual Intervention - Task Recovery:**
- Location: `SKILL.md` (section "Recovery After Interruption")
- Triggers: Operator detects monitor failure or wants to manually resume task
- Responsibilities: Connect to tmux session, invoke agent-specific resume command

## Error Handling

**Strategy:** Layered fallback with explicit failure states

**Patterns:**

- **File-based state validation:** Monitor validates Codex session ID format before using it to prevent command injection (lines 88-91 in `monitor.sh`)
- **Session disappearance handling:** If session vanishes during monitor check, exit cleanly rather than error (lines 59-62, 117-119)
- **Missing session ID for Codex:** If Codex session ID file doesn't exist, stop monitoring rather than guess (lines 94-97)
- **Agent-specific limits:** Pi agent has no resume capability, so monitor explicitly stops for Pi (lines 107-110)
- **Deadline enforcement:** Monitor stops after 5 hours wall-clock to prevent indefinite recovery attempts (lines 43-46)
- **Shell sanitization:** Session names and agent types validated with restrictive regex patterns (lines 31-34, 25-28)
- **Prompt injection prevention:** Prompts delivered via file read, not string interpolation, preventing shell escapes

## Cross-Cutting Concerns

**Logging:** None built-in; monitor script echoes status to stdout/stderr with timestamps implicit in cron/orchestrator logs. Task output accumulated in event files (`events.jsonl`). Orchestrator responsible for shipping logs.

**Validation:** Restrict session names to `[A-Za-z0-9._-]` (line 31). Restrict agent types to known set (lines 25-27). Restrict Codex session IDs to `[A-Za-z0-9_-]` (line 88). Validate prompt file before reading (implicit in orchestrator's write tool).

**Security:** Temp directories created with `mktemp -d` and `chmod 700` to prevent other users from accessing task state. Prompts stored as files to prevent shell injection. Session ID validation before command dispatch. No inline secrets in command strings (all via env vars or files).

---

*Architecture analysis: 2026-02-18*
