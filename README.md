# Resilient Coding Agent

[![ClawHub](https://img.shields.io/badge/ClawHub-resilient--coding--agent-blue)](https://clawhub.com/cosformula/resilient-coding-agent)
[![Version](https://img.shields.io/badge/version-0.2.0-green)](https://clawhub.com/cosformula/resilient-coding-agent)
[![GitHub stars](https://img.shields.io/github/stars/cosformula/resilient-coding-agent-skill)](https://github.com/cosformula/resilient-coding-agent-skill)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/cosformula/resilient-coding-agent-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/cosformula/resilient-coding-agent-skill/actions/workflows/ci.yml)
[![Publish](https://github.com/cosformula/resilient-coding-agent-skill/actions/workflows/clawhub-publish.yml/badge.svg)](https://github.com/cosformula/resilient-coding-agent-skill/actions/workflows/clawhub-publish.yml)

Run long-running coding agents (Codex CLI, Claude Code, OpenCode, Pi) in tmux sessions that survive orchestrator restarts, with periodic health checks and automatic resume on interruption.

## Problem

AI coding agents running long tasks (refactors, full codebase reviews, complex builds) get killed when the orchestrator process restarts. You lose progress, get no completion notification, and have to start over.

## Solution

Decouple the coding agent from the orchestrator by running it in a tmux session. The agent keeps running regardless of what happens to the orchestrator. A monitor loop can check health with `tmux has-session` and `tmux capture-pane`, detect likely crashes, and trigger native resume commands in the same tmux session.

## Features

- Runs coding agents in `tmux` sessions so tasks survive orchestrator restarts
- Supports periodic health monitoring (`tmux has-session` + `tmux capture-pane`)
- Detects likely agent exits from shell-prompt return and exit indicators in recent output
- Auto-recovers with native resume commands (`codex exec resume <session-id>`, `claude --resume`, `opencode run "Continue"`)
- Supports completion notifications via marker files, system events, or webhooks

## Supported Agents

- **Codex CLI** (with `codex exec resume` for recovery)
- **Claude Code** (with `claude --resume` for recovery)
- **OpenCode**
- **Pi Coding Agent**

## Install

### Via npx skills (any agent)

```bash
npx skills add cosformula/resilient-coding-agent-skill
```

### Via ClawHub (OpenClaw)

```bash
clawhub install resilient-coding-agent
```

### Manual

```bash
git clone https://github.com/cosformula/resilient-coding-agent-skill.git
```

## Quick Start

```bash
# Start a long Codex task in tmux
SESSION="codex-refactor"
TMPDIR=$(mktemp -d) && chmod 700 "$TMPDIR"

# Write prompt (in practice, use orchestrator's write tool)
echo "Refactor auth module" > "$TMPDIR/prompt"

tmux new-session -d -s "$SESSION" -e "TASK_TMPDIR=$TMPDIR"
tmux send-keys -t "$SESSION" 'cd ~/project && set -o pipefail && codex exec --full-auto --json "$(cat $TASK_TMPDIR/prompt)" | tee $TASK_TMPDIR/events.jsonl && openclaw system event --text "Codex done: auth refactor" --mode now; echo "__TASK_DONE__"' Enter

# Save this task's Codex session ID (safer than resume --last when multiple tasks run)
until [ -s "$TMPDIR/codex-session-id" ]; do
  if command -v jq &>/dev/null; then
    jq -r 'select(.thread_id) | .thread_id' "$TMPDIR/events.jsonl" 2>/dev/null | head -n 1 > "$TMPDIR/codex-session-id"
  else
    grep -oE '"thread_id":"[^"]+"' "$TMPDIR/events.jsonl" 2>/dev/null | head -n 1 | cut -d'"' -f4 > "$TMPDIR/codex-session-id"
  fi
  sleep 1
done

# Check progress
tmux capture-pane -t "$SESSION" -p -S -100

# If Codex crashes, resume this exact session
CODEX_SESSION_ID="$(cat "$TMPDIR/codex-session-id")"
tmux send-keys -t "$SESSION" "codex exec resume $CODEX_SESSION_ID \"Continue the refactor\"" Enter

# Or run the monitor script for automated crash detection + resume
./scripts/monitor.sh "$SESSION" codex
```

## Requirements

- `tmux` installed
- At least one coding agent CLI (codex, claude, opencode, or pi)
- `bash` for the health-monitor script (`scripts/monitor.sh`)

## Compatibility

- **macOS / Linux**: Fully supported. Install tmux via package manager.
- **Windows**: Requires WSL. Native Windows is not supported (no tmux).
- **Shell**: Health monitoring detects bash (`$ `), zsh (`% `), and fish (`> `) prompts.

## License

MIT, Copyright cosformula
