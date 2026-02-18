#!/usr/bin/env bash
#
# Monitor a Claude Code session running in tmux.
# Detects completion via done-file and crashes via PID liveness (kill -0).
# Auto-resumes crashed sessions using `claude -c`.
#
# Usage:
#   ./scripts/monitor.sh <tmux-session> <task-tmpdir>
#
#   tmux-session  Name of the tmux session (e.g. claude-refactor-auth)
#   task-tmpdir   Path to the task's secure temp directory ($TMPDIR from launch)
#
# Retry: 3min base, doubles on each consecutive failure, resets when agent
# is running normally. Stops after 5 hours wall-clock.

set -uo pipefail

SESSION="${1:?Usage: monitor.sh <tmux-session> <task-tmpdir>}"
TASK_TMPDIR="${2:?Usage: monitor.sh <tmux-session> <task-tmpdir>}"

# Sanitize session name: only allow alphanumeric, dash, underscore, dot
if ! printf '%s' "$SESSION" | grep -Eq '^[A-Za-z0-9._-]+$'; then
  echo "Invalid session name: $SESSION (only alphanumeric, dash, underscore, dot allowed)" >&2
  exit 1
fi

# Validate TASK_TMPDIR is a directory
if [ ! -d "$TASK_TMPDIR" ]; then
  echo "TASK_TMPDIR not a directory: $TASK_TMPDIR" >&2
  exit 1
fi

RETRY_COUNT=0
START_TS="$(date +%s)"
DEADLINE_TS=$(( START_TS + 18000 ))  # 5 hours wall-clock

while true; do
  NOW_TS="$(date +%s)"
  if [ "$NOW_TS" -ge "$DEADLINE_TS" ]; then
    echo "Retry timeout reached (5h wall-clock). Stopping monitor."
    break
  fi

  INTERVAL=$(( 180 * (2 ** RETRY_COUNT) ))

  # Cap sleep so we don't overshoot the 5h deadline
  REMAINING=$(( DEADLINE_TS - NOW_TS ))
  if [ "$INTERVAL" -gt "$REMAINING" ]; then
    INTERVAL="$REMAINING"
  fi

  if tmux has-session -t "$SESSION" 2>/dev/null; then
    # Read PID from file (may not exist yet if agent is still starting)
    if [ -f "$TASK_TMPDIR/pid" ]; then
      PID="$(cat "$TASK_TMPDIR/pid")"
    else
      # PID file not yet written -- agent still starting
      sleep "$INTERVAL"
      continue
    fi

    # Priority 1: Done-file = task completed
    if [ -f "$TASK_TMPDIR/done" ]; then
      EXIT_CODE="$(cat "$TASK_TMPDIR/exit_code" 2>/dev/null || echo "unknown")"
      echo "Task completed with exit code: $EXIT_CODE"
      break
    fi

    # Priority 2: PID dead = crash (no done-file means abnormal exit)
    if ! kill -0 "$PID" 2>/dev/null; then
      RETRY_COUNT=$(( RETRY_COUNT + 1 ))
      echo "Crash detected (PID $PID gone). Resuming Claude Code (retry #$RETRY_COUNT)"
      tmux send-keys -t "$SESSION" 'claude -c' Enter
      # Grace period: after resume, new process needs time to start.
      # PID file is stale (contains dead PID). Phase 4 will address PID re-capture.
      # For now, sleep longer than the normal interval to avoid rapid resume loops.
      sleep 10
      continue
    fi

    # Priority 3: Process alive, no completion -- healthy
    RETRY_COUNT=0
  else
    echo "tmux session $SESSION no longer exists. Stopping monitor."
    break
  fi

  sleep "$INTERVAL"
done
