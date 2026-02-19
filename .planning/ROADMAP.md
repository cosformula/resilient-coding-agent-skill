# Roadmap: Resilient Coding Agent Skill Rewrite

## Overview

Rewrite the OpenClaw "Muscles" skill from a multi-agent, heuristic-based system into a single-agent (Claude Code), deterministic, model-aware delegation layer. The journey starts by deleting dead code and establishing contracts (Phase 1), then builds the three detection signals that replace regex heuristics (Phase 2), adds structured task state for Brain queries (Phase 3), rewrites the monitor to consume those signals deterministically (Phase 4), and finishes with Brain integration validation (Phase 5). Each phase unblocks the next -- detection signals must exist before the manifest can populate them, and the manifest must exist before the monitor can update it.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation** - Remove multi-agent dead code, rewrite SKILL.md scope, add model routing, finalize task directory schema
- [ ] **Phase 2: Detection Infrastructure** - PID tracking, done-file markers, continuous output capture with ANSI stripping
- [ ] **Phase 3: Structured State** - JSON task manifest with atomic writes and output tail on completion
- [ ] **Phase 4: Monitor Rewrite** - Three-layer deterministic detection replacing regex heuristics
- [ ] **Phase 5: Brain Integration** - All-tasks-via-tmux policy and end-to-end lifecycle validation

## Phase Details

### Phase 1: Foundation
**Goal**: A clean, single-agent, model-aware, aggressively-scoped skill with a finalized task directory schema that all subsequent phases build on
**Depends on**: Nothing (first phase)
**Requirements**: TS-9, TS-10, TS-5, TS-7, TS-8, D-4
**Success Criteria** (what must be TRUE):
  1. SKILL.md references only Claude Code -- no mention of Codex, OpenCode, or Pi anywhere in the file
  2. SKILL.md "When to Use" section claims ALL non-chat tasks with no duration threshold
  3. The tmux send-keys command template includes a `--model` flag that maps `opus` to `claude-opus-4-6` and `sonnet` to `claude-sonnet-4-6`
  4. The task directory layout (prompt, pid, output.log, manifest.json, done, exit_code) is documented as a specification in SKILL.md or a companion doc
  5. monitor.sh contains no agent-type case branches -- only Claude Code resume logic remains
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md -- Rewrite SKILL.md: single-agent, model-aware, aggressive scope, task directory schema
- [x] 01-02-PLAN.md -- Simplify monitor.sh: remove agent-type branching, update resume command

### Phase 2: Detection Infrastructure
**Goal**: Reliable, filesystem-based task state signals that eliminate regex heuristics -- process liveness via PID, task completion via done-file, and continuous output via pipe-pane
**Depends on**: Phase 1
**Requirements**: TS-1, TS-2, TS-3, TS-4
**Success Criteria** (what must be TRUE):
  1. After launching a Claude Code session, the actual claude child PID (not the shell pane PID) is written to `$TMPDIR/pid` and `kill -0` on that PID correctly reflects process liveness
  2. When Claude Code exits, `$TMPDIR/done` exists and `$TMPDIR/exit_code` contains the numeric exit code -- written via shell wrapper, not `exec`
  3. From the moment the tmux session is created, all terminal output streams continuously to `$TMPDIR/output.log` via `tmux pipe-pane`
  4. The output.log file contains clean text with ANSI escape sequences stripped -- no color codes, cursor movement, or progress bar artifacts
**Plans**: 2 plans

Plans:
- [ ] 02-01-PLAN.md -- Update SKILL.md: shell wrapper with PID capture, pipe-pane output capture with ANSI stripping, done-file protocol
- [ ] 02-02-PLAN.md -- Rewrite monitor.sh detection: done-file check + PID liveness replace scrollback regex parsing

### Phase 3: Structured State
**Goal**: A machine-readable JSON task manifest that the Brain can query for any task's status, output, and result without parsing ad-hoc files
**Depends on**: Phase 2
**Requirements**: TS-6, D-5, D-8
**Success Criteria** (what must be TRUE):
  1. `$TMPDIR/manifest.json` exists at task start and contains task_name, model, project_dir, session_name, pid, tmpdir, started_at, and status fields
  2. All manifest writes use the write-to-tmp + `mv` atomic pattern -- a concurrent reader never sees partial or corrupt JSON
  3. When a task completes, manifest.json is updated with finished_at, exit_code, status (completed/failed), and an output_tail field containing the last 100 lines of output.log
**Plans**: 1 plan

Plans:
- [x] 03-01-PLAN.md -- Add JSON task manifest to SKILL.md: initial creation, PID update, completion update with output_tail

### Phase 4: Monitor Rewrite
**Goal**: A deterministic monitor that detects completion, crashes, and hangs using filesystem signals instead of regex heuristics, with configurable intervals and clean resource management
**Depends on**: Phase 3
**Requirements**: D-3, D-1, D-6, D-7
**Success Criteria** (what must be TRUE):
  1. The monitor checks done-file FIRST in every loop iteration -- if `$TMPDIR/done` exists, it declares success immediately regardless of other signals
  2. If the done-file is absent and `kill -0 $PID` fails (process dead), the monitor dispatches `claude --resume` and updates manifest status to "crashed"
  3. If the process is alive but output.log mtime exceeds the staleness threshold, the monitor enters a grace period (default 30s) before taking action -- it never kills on the first stale check
  4. Monitor intervals are configurable via MONITOR_BASE_INTERVAL (default 30s), MONITOR_MAX_INTERVAL (default 5m), and MONITOR_DEADLINE (default 5h) environment variables
  5. When the deadline is reached or retries are exhausted, the monitor updates manifest status to "abandoned", fires an `openclaw system event` notification, and cleans up the tmux session via EXIT trap
**Plans**: 1 plan

Plans:
- [ ] 04-01-PLAN.md -- Rewrite monitor.sh with three-layer detection, configurable intervals, manifest updates, EXIT trap; update SKILL.md Health Monitoring docs

### Phase 5: Brain Integration
**Goal**: Every task the Brain delegates flows through tmux with full reliability guarantees, and results are retrievable after session cleanup
**Depends on**: Phase 4
**Requirements**: D-2
**Success Criteria** (what must be TRUE):
  1. SKILL.md contains no "fast path" or duration-based routing -- every task, regardless of expected duration, uses the tmux session + monitor flow
  2. The Brain can retrieve task results via `tail -n 50 $TMPDIR/output.log` or by reading `output_tail` from manifest.json, even after the tmux session has been killed
  3. An end-to-end task lifecycle (delegate -> execute -> crash -> resume -> complete -> retrieve results) works without manual intervention
**Plans**: 1 plan

Plans:
- [ ] 05-01-PLAN.md -- Edit SKILL.md: remove duration-based conditional, make monitor mandatory in checklist, document $TMPDIR persistence

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 2/2 | Complete | 2026-02-18 |
| 2. Detection Infrastructure | 2/2 | Complete | 2026-02-18 |
| 3. Structured State | 1/1 | Complete | 2026-02-18 |
| 4. Monitor Rewrite | 0/1 | Not started | - |
| 5. Brain Integration | 0/1 | Not started | - |
