# Phase 4: Monitor Rewrite - Research

**Researched:** 2026-02-19
**Domain:** Bash shell scripting for process monitoring -- mtime staleness detection, grace period state machine, configurable env vars, EXIT trap cleanup, manifest status updates
**Confidence:** HIGH

## Summary

Phase 4 rewrites `scripts/monitor.sh` from the basic two-signal detection established in Phase 2 (done-file + PID liveness) into a full three-layer deterministic monitor that adds hang detection via output.log mtime staleness, configurable intervals via environment variables, grace period state management, manifest status updates on crash/abandoned transitions, openclaw system event notification on deadline exhaustion, and clean EXIT trap resource management.

The existing 89-line monitor.sh (as of Phase 3 completion) already has the correct three-priority detection order and session validation. Phase 4 adds four new capabilities on top of that foundation: (1) a staleness check against output.log mtime with a grace period before acting, (2) env var-driven interval configuration replacing the hard-coded 180s base and 5h deadline, (3) manifest status updates using the `jq '. + {...}'` merge pattern established in Phase 3, and (4) an EXIT trap that fires on deadline, abandonment, or script termination.

The primary complexity is the grace period state machine: when output.log mtime exceeds the staleness threshold, the monitor must not act immediately. It records a `STALE_SINCE` timestamp, then on subsequent loop iterations checks whether the grace period has elapsed before dispatching a resume. This requires tracking state across loop iterations, which is cleanly handled with a bash variable. All patterns are verified on macOS (darwin 25.3.0) and confirmed portable.

**Primary recommendation:** Implement Phase 4 as a single rewrite of monitor.sh -- the script is small enough (target ~130 lines) that incremental editing is error-prone. Replace entirely from the Phase 2/3 foundation but preserve all safety patterns (session name validation, TASK_TMPDIR directory check, done-file priority-first).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| D-1 | Hang detection -- detect agents alive but stuck via output.log mtime staleness as proxy heartbeat | `stat -f %m` (macOS) / `stat -c %Y` (Linux) with platform-detection helper. Staleness = `NOW - MTIME > THRESHOLD`. Threshold defaults to MONITOR_BASE_INTERVAL. See "Pattern 3: Staleness Check" and "Pitfall 2: stat Portability". Prior decision: output.log mtime over synthetic touch-file (roadmap). |
| D-3 | Rewritten monitor -- three-layer detection: done-file first, then PID liveness, then output staleness | Layer ordering matches P12 prevention (done-file checked first eliminates race). PID liveness via `kill -0`. Staleness as third layer only when process is alive and no done-file. See "Architecture Patterns" section. |
| D-6 | Configurable monitor intervals -- MONITOR_BASE_INTERVAL / MONITOR_MAX_INTERVAL / MONITOR_DEADLINE via env vars | Bash `${VAR:-default}` defaulting pattern. BASE=30s, MAX=300s (5m), DEADLINE=18000s (5h). Exponential backoff: `BASE * 2^RETRY_COUNT` capped at MAX. See "Pattern 1: Env Var Configuration" and verification output. |
| D-7 | Retry exhaustion notification -- final manifest update (status: abandoned) + `openclaw system event` when deadline hit | jq `. + {status: "abandoned", ...}` merge pattern (verified). `openclaw system event --text "..." --mode now` via `;` (fire-and-forget). EXIT trap handles both deadline and signal-based termination. See "Pattern 4: EXIT Trap Cleanup" and "Pattern 5: Manifest Status Updates". |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | 3.2+ (macOS system) | Shell scripting for monitor loop, arithmetic, traps | Already the established monitor language; no new dependencies |
| kill | builtin | `kill -0 $PID` PID liveness check | Zero overhead; bash builtin; established in Phase 2 |
| stat | system (macOS: -f %m / Linux: -c %Y) | Read output.log mtime for staleness detection | System utility; requires platform-detection wrapper (see Pitfall 2) |
| jq | 1.7.1 (system /usr/bin/jq) | Manifest status updates (crashed, abandoned, retry_count, last_checked_at) | Established in Phase 3; atomic merge pattern already verified |
| date | system | Epoch timestamps for deadline and staleness math | `date +%s` is portable on macOS and Linux |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| tmux send-keys | 2.6+ | Dispatch `claude -c` resume command | On crash detection (PID dead, no done-file) |
| tmux kill-session | 2.6+ | Clean session teardown in EXIT trap | On deadline exhaustion or abandonment |
| tmux pipe-pane | 2.6+ | Disable pipe-pane before kill-session | In EXIT trap before kill-session (prevents orphan perl processes -- established P4 prevention) |
| openclaw | system | `openclaw system event` notification | On deadline exhaustion (abandoned state) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| output.log mtime as heartbeat | Synthetic touch-file heartbeat loop in tmux | Roadmap decision: output.log mtime preferred -- measures real progress, no extra infrastructure required |
| Bash state variable for grace period | External temp file (`$TASK_TMPDIR/stale_since`) | Bash variable is simpler, zero I/O; file survives monitor restart but adds complexity. Monitor restart is not a requirement. |
| Shell `stat` with platform detection | `perl -e 'print (stat("file"))[9]'` | Perl is available (used in Phase 2 pipe-pane), provides one-liner cross-platform mtime; but stat is simpler and readable |

## Architecture Patterns

### Phase 4 Changes to Existing Files

```
scripts/monitor.sh        # REWRITE: Add staleness check with grace period
                          #          Add MONITOR_BASE_INTERVAL/MAX/DEADLINE env vars
                          #          Add manifest status updates on crash/abandoned
                          #          Add EXIT trap for session cleanup
                          #          Adjust interval math to use configurable vars

SKILL.md                  # MINOR UPDATE (if needed): Document Phase 4 env vars
                          # Monitor section already accurate for the core flow
```

No new files are created. The rewrite is entirely contained in `scripts/monitor.sh`.

### Monitor Loop State Machine

The monitor now tracks two state variables across loop iterations:

```
RETRY_COUNT   - Increments on each crash detection; resets when healthy
STALE_SINCE   - Timestamp (epoch) of when staleness was first detected; "" when not stale
```

State transitions:

```
HEALTHY:        RETRY_COUNT=0, STALE_SINCE=""
STALE:          RETRY_COUNT unchanged, STALE_SINCE=<epoch>
GRACE_EXPIRED:  Enter if STALE_SINCE != "" and NOW-STALE_SINCE >= GRACE_PERIOD
CRASHED:        done-file absent, kill -0 fails
RESUMED:        claude -c dispatched, STALE_SINCE="", RETRY_COUNT incremented
ABANDONED:      deadline reached -- EXIT trap fires
```

### Pattern 1: Env Var Configuration

All three interval parameters use bash default-value expansion at the top of the script:

```bash
# Configurable monitor intervals (override via env)
MONITOR_BASE_INTERVAL="${MONITOR_BASE_INTERVAL:-30}"    # seconds; default 30s
MONITOR_MAX_INTERVAL="${MONITOR_MAX_INTERVAL:-300}"     # seconds; default 5m
MONITOR_DEADLINE="${MONITOR_DEADLINE:-18000}"           # seconds; default 5h

# Grace period before acting on stale output (not a separate env var -- tied to base interval)
MONITOR_GRACE_PERIOD="${MONITOR_GRACE_PERIOD:-30}"      # seconds; default 30s
```

**Verified:** `${VAR:-default}` works in bash 3.2+. All arithmetic operations on these values work with `$(( ))`. See shell verification output above.

**Interval arithmetic (exponential backoff with cap):**

```bash
INTERVAL=$(( MONITOR_BASE_INTERVAL * (2 ** RETRY_COUNT) ))
if [ "$INTERVAL" -gt "$MONITOR_MAX_INTERVAL" ]; then
  INTERVAL=$MONITOR_MAX_INTERVAL
fi
# Also cap so we don't overshoot deadline
REMAINING=$(( DEADLINE_TS - NOW_TS ))
if [ "$INTERVAL" -gt "$REMAINING" ] && [ "$REMAINING" -gt 0 ]; then
  INTERVAL=$REMAINING
fi
```

**Verified:** With BASE=30, RETRY_COUNT=3: `30 * 8 = 240s`, capped at MAX=300 gives 240s. Correct.

### Pattern 2: Deadline Enforcement (EXIT Trap)

The deadline is converted to an epoch timestamp at script start. The loop checks it every iteration before sleeping. The EXIT trap fires on script exit (deadline reached, signal received, or manual kill):

```bash
START_TS="$(date +%s)"
DEADLINE_TS=$(( START_TS + MONITOR_DEADLINE ))

cleanup() {
  local exit_code=$?
  # Update manifest to abandoned (if not already done/completed)
  if [ -f "$TASK_TMPDIR/manifest.json" ] && [ ! -f "$TASK_TMPDIR/done" ]; then
    jq \
      --arg status "abandoned" \
      --arg abandoned_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '. + {status: $status, abandoned_at: $abandoned_at}' \
      "$TASK_TMPDIR/manifest.json" \
      > "$TASK_TMPDIR/manifest.json.tmp" \
      && mv "$TASK_TMPDIR/manifest.json.tmp" "$TASK_TMPDIR/manifest.json"
    openclaw system event --text "Task abandoned: $SESSION" --mode now
  fi
  # Disable pipe-pane and clean up session
  tmux pipe-pane -t "$SESSION" 2>/dev/null || true
  tmux kill-session -t "$SESSION" 2>/dev/null || true
}
trap cleanup EXIT
```

**Key details:**
- `|| true` on tmux commands prevents trap from failing (session may already be gone)
- Guard `[ ! -f "$TASK_TMPDIR/done" ]` prevents updating manifest to "abandoned" for a completed task
- `openclaw system event` uses `;` implicitly (inside cleanup, failure is non-fatal)
- Trap fires on normal exit (deadline), INT, TERM, and ERR (with `set -e`)

**Verified:** EXIT trap fires on normal `exit` in bash. See trap_test.sh verification above.

### Pattern 3: Staleness Check (Hang Detection, D-1)

The staleness check is Layer 3 -- only reached when done-file is absent AND PID is alive. It uses output.log mtime as the proxy heartbeat (roadmap decision).

**Platform-detection helper (addresses the known blocker from STATE.md):**

```bash
# get_mtime: return epoch seconds of file mtime, cross-platform
# Usage: MTIME=$(get_mtime "$file")
get_mtime() {
  local file="$1"
  stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0
}
```

**Staleness check with grace period:**

```bash
# Layer 3: Output staleness (process alive, no done-file)
if [ -f "$TASK_TMPDIR/output.log" ]; then
  OUTPUT_MTIME=$(get_mtime "$TASK_TMPDIR/output.log")
  NOW_TS="$(date +%s)"
  OUTPUT_AGE=$(( NOW_TS - OUTPUT_MTIME ))
  STALENESS_THRESHOLD=$(( MONITOR_BASE_INTERVAL * 3 ))  # 3x base = 90s default

  if [ "$OUTPUT_AGE" -gt "$STALENESS_THRESHOLD" ]; then
    # Output is stale -- start or check grace period
    if [ -z "$STALE_SINCE" ]; then
      # First detection: record timestamp, do not act yet
      STALE_SINCE="$NOW_TS"
      echo "Output stale (${OUTPUT_AGE}s). Grace period started."
    else
      GRACE_ELAPSED=$(( NOW_TS - STALE_SINCE ))
      if [ "$GRACE_ELAPSED" -ge "$MONITOR_GRACE_PERIOD" ]; then
        # Grace period expired -- treat as crash, resume
        echo "Grace period expired (${GRACE_ELAPSED}s). Resuming."
        STALE_SINCE=""
        RETRY_COUNT=$(( RETRY_COUNT + 1 ))
        # Update manifest
        jq --arg status "crashed" --argjson retry_count "$RETRY_COUNT" \
           --arg last_checked_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '. + {status: $status, retry_count: $retry_count, last_checked_at: $last_checked_at}' \
           "$TASK_TMPDIR/manifest.json" > "$TASK_TMPDIR/manifest.json.tmp" \
           && mv "$TASK_TMPDIR/manifest.json.tmp" "$TASK_TMPDIR/manifest.json"
        tmux send-keys -t "$SESSION" 'claude -c' Enter
        sleep 10
        continue
      fi
    fi
  else
    # Output is fresh -- clear any stale state
    STALE_SINCE=""
    RETRY_COUNT=0
  fi
fi
```

**Key design decisions:**
- Grace period uses `STALE_SINCE` bash variable (not a file) -- simpler, zero I/O, sufficient (monitor restart not required)
- `STALENESS_THRESHOLD` defaults to `3 * MONITOR_BASE_INTERVAL` (90s with default 30s base) -- tunable indirectly via MONITOR_BASE_INTERVAL, or could be a dedicated env var
- Stale output but process alive: enter grace period. If grace period expires without fresh output: resume
- Fresh output (output.log mtime updated since last check): clear STALE_SINCE, reset RETRY_COUNT -- healthy
- The success criteria says "if the process is alive but output.log mtime exceeds the staleness threshold" -- this is the exact condition checked
- Note: The success criteria says "default 30s" grace period. This matches MONITOR_GRACE_PERIOD default.

### Pattern 4: Manifest Status Updates

The monitor adds fields to manifest.json using the `jq '. + {...}'` merge pattern established in Phase 3. The monitor writes to manifest on two events:

**On crash detection (PID dead, no done-file):**

```bash
RETRY_COUNT=$(( RETRY_COUNT + 1 ))
jq \
  --arg status "crashed" \
  --argjson retry_count "$RETRY_COUNT" \
  --arg last_checked_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '. + {status: $status, retry_count: $retry_count, last_checked_at: $last_checked_at}' \
  "$TASK_TMPDIR/manifest.json" \
  > "$TASK_TMPDIR/manifest.json.tmp" \
  && mv "$TASK_TMPDIR/manifest.json.tmp" "$TASK_TMPDIR/manifest.json"
```

**On deadline/abandoned (in EXIT trap, see Pattern 2 above):**

```bash
jq \
  --arg status "abandoned" \
  --arg abandoned_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '. + {status: $status, abandoned_at: $abandoned_at}' \
  "$TASK_TMPDIR/manifest.json" \
  > "$TASK_TMPDIR/manifest.json.tmp" \
  && mv "$TASK_TMPDIR/manifest.json.tmp" "$TASK_TMPDIR/manifest.json"
```

**Verified:** Both patterns work with jq 1.7.1 on macOS. The `. + {...}` merge preserves all existing fields and adds/overwrites specified keys. See verification output above.

### Pattern 5: Resume Command

The resume command is `claude -c` (continue most recent conversation in the working directory). This is the established convention from Phase 1 and Phase 2.

**Important:** The success criteria for Phase 4 says "dispatches `claude --resume`" -- this conflicts with the established convention of `claude -c`. Based on the Claude CLI help output (verified), both `-c`/`--continue` and `-r`/`--resume [session-id]` exist. The established decision from Phase 1 is `claude -c` (simpler, one conversation per tmux session). The success criterion's "claude --resume" appears to be informal language for "resume command" not a specific flag. Use `claude -c` to be consistent with Phase 1/2 decisions.

### Full Loop Structure

```bash
RETRY_COUNT=0
STALE_SINCE=""
START_TS="$(date +%s)"
DEADLINE_TS=$(( START_TS + MONITOR_DEADLINE ))

while true; do
  NOW_TS="$(date +%s)"

  # Deadline check
  if [ "$NOW_TS" -ge "$DEADLINE_TS" ]; then
    echo "Deadline reached (${MONITOR_DEADLINE}s). Stopping monitor."
    exit 1  # EXIT trap fires
  fi

  # Calculate sleep interval
  INTERVAL=$(( MONITOR_BASE_INTERVAL * (2 ** RETRY_COUNT) ))
  [ "$INTERVAL" -gt "$MONITOR_MAX_INTERVAL" ] && INTERVAL=$MONITOR_MAX_INTERVAL
  REMAINING=$(( DEADLINE_TS - NOW_TS ))
  [ "$INTERVAL" -gt "$REMAINING" ] && [ "$REMAINING" -gt 0 ] && INTERVAL=$REMAINING

  if tmux has-session -t "$SESSION" 2>/dev/null; then

    # Wait for PID file
    if [ ! -f "$TASK_TMPDIR/pid" ]; then
      sleep "$INTERVAL"
      continue
    fi
    PID="$(cat "$TASK_TMPDIR/pid")"

    # Layer 1: Done-file = success
    if [ -f "$TASK_TMPDIR/done" ]; then
      EXIT_CODE="$(cat "$TASK_TMPDIR/exit_code" 2>/dev/null || echo "unknown")"
      echo "Task completed with exit code: $EXIT_CODE"
      exit 0  # EXIT trap fires (but guard prevents abandoned update)
    fi

    # Layer 2: PID liveness
    if ! kill -0 "$PID" 2>/dev/null; then
      STALE_SINCE=""  # Clear stale state on crash
      RETRY_COUNT=$(( RETRY_COUNT + 1 ))
      echo "Crash detected (PID $PID gone). Resuming (retry #$RETRY_COUNT)"
      # Update manifest
      jq ... '. + {status: "crashed", retry_count: $retry_count, ...}' ...
      tmux send-keys -t "$SESSION" 'claude -c' Enter
      sleep 10
      continue
    fi

    # Layer 3: Output staleness (process alive, no done-file)
    # [staleness check with grace period -- see Pattern 3]

    # Healthy: reset
    RETRY_COUNT=0

  else
    echo "tmux session $SESSION no longer exists. Stopping monitor."
    exit 0
  fi

  sleep "$INTERVAL"
done
```

### Anti-Patterns to Avoid

- **DO NOT use `stat` without platform detection:** `stat -f %m` is macOS; `stat -c %Y` is Linux. Always use the `get_mtime()` helper.
- **DO NOT kill immediately on first stale check:** The grace period is required. Acting on the first stale observation would kill agents during long reasoning steps.
- **DO NOT reset `STALE_SINCE` to "" before acting on grace period expiry:** Clear it after dispatching resume, not before the check.
- **DO NOT put manifest updates after `touch done` or after deadline exit without guarding:** The EXIT trap must check `[ ! -f "$TASK_TMPDIR/done" ]` to avoid overwriting a completed task's manifest.
- **DO NOT use `&&` for openclaw in EXIT trap:** Use `;` (fire-and-forget). Notification failure must not prevent cleanup.
- **DO NOT forget `|| true` on tmux commands in EXIT trap:** Session or pipe-pane may already be gone; failures in EXIT trap cause unexpected behavior.
- **DO NOT use `claude --resume` for crash recovery:** Use `claude -c` (established in Phase 1; `-c` is the `--continue` flag, not `--resume`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-platform mtime | Separate macOS/Linux code paths inline | `get_mtime()` helper function | Single testable abstraction; isolates the platform difference |
| Grace period state | External temp file for STALE_SINCE | Bash variable `STALE_SINCE` | Zero I/O, simpler; monitor restart not a requirement |
| Manifest status update | String concatenation of JSON | `jq '. + {...}'` merge (established Phase 3) | Same pattern already in use; handles escaping; atomic via tmp+mv |
| Interval capping | Complex conditional tree | Simple `[ "$X" -gt "$MAX" ] && X=$MAX` | Two conditions (max cap + remaining deadline cap); stay simple |
| Cleanup on exit | Duplicate cleanup logic at each exit point | Single `trap cleanup EXIT` | Bash EXIT trap is the canonical pattern; fires on all exit paths |

**Key insight:** The monitor's complexity comes from the state machine (RETRY_COUNT + STALE_SINCE tracking across iterations), not from any individual operation. Keep each operation simple; let the loop structure encode the state.

## Common Pitfalls

### Pitfall 1: Grace Period Race (P12 variant)
**What goes wrong:** Checking staleness but not done-file first. Agent writes done-file while output.log mtime is stale (agent finished but hadn't output recently). Monitor sees stale mtime, enters grace period, and eventually dispatches resume -- restarting a task that already completed.
**Why it happens:** Staleness check placed before done-file check in loop.
**How to avoid:** Done-file is ALWAYS Layer 1, checked before any other signal. The staleness check (Layer 3) is only reached when done-file is absent AND PID is alive.
**Warning signs:** Monitor dispatches `claude -c` immediately after seeing done-file; rapid resume loop on completed tasks.

### Pitfall 2: stat Portability (STATE.md blocker)
**What goes wrong:** `stat -f %m` works on macOS but silently fails on Linux (returns error, outputs nothing). `stat -c %Y` works on Linux but fails on macOS. Code using either one directly breaks on the other platform.
**Why it happens:** BSD stat (macOS) and GNU stat (Linux) use incompatible flag syntax.
**How to avoid:** Use the `get_mtime()` helper that tries both: `stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0`. The `|| echo 0` fallback ensures the file is treated as epoch 0 (infinitely old) if stat fails -- safe failure mode.
**Verified:** `stat -f %m /etc/hosts` works on macOS (darwin 25.3.0); returns epoch seconds. Linux fallback path verified syntactically.
**Warning signs:** Staleness check always triggers immediately (mtime returned as 0); output.log never appears fresh.

### Pitfall 3: Stale PID After Resume (existing, deferred from Phase 2)
**What goes wrong:** After `claude -c` resume, the PID file contains the old (dead) PID. The new Claude process has a new PID. The monitor's next PID liveness check finds the old PID dead again and resumes infinitely.
**Why it happens:** Phase 2 deferred PID re-capture to Phase 4. The wrapper that wrote the original PID file is no longer running after crash.
**How to avoid:** The Phase 4 approach: after dispatching resume, `sleep 10` then `continue`. On the next iteration, re-read the PID file -- the wrapper in the tmux session (if it re-runs) will overwrite the PID file with the new PID. However, `claude -c` is the resume command inside tmux which restarts Claude but the shell wrapper does not re-run. The PID file will still be stale.
**Resolution strategy:** After resume, the monitor should treat the process as potentially alive for one full interval before re-checking PID. The `sleep 10; continue` approach jumps to the next loop iteration which sleeps another `INTERVAL` before checking PID again -- giving the resumed process time to start. The PID check will still find the old PID dead. The monitor will see "crash detected" again on the next iteration, increment RETRY_COUNT, and retry. This retry loop is bounded by MONITOR_DEADLINE.
**Practical impact:** The resume-then-retry loop works because `claude -c` starts Claude which eventually writes a new PID via the session wrapper (if the tmux session still has the shell with $TASK_TMPDIR set). Phase 4 does not fully solve the PID staleness problem -- it mitigates it with the grace period and retry count.
**Warning signs:** Rapid consecutive "crash detected" messages; RETRY_COUNT incrementing faster than expected.

### Pitfall 4: EXIT Trap Overwriting Completed Manifest
**What goes wrong:** Monitor exits after seeing done-file (task completed). EXIT trap runs. Without a guard, the trap sets `status: abandoned` -- overwriting the task's `status: completed`.
**Why it happens:** EXIT trap fires on all exit paths including normal completion.
**How to avoid:** Guard in EXIT trap: `if [ -f "$TASK_TMPDIR/manifest.json" ] && [ ! -f "$TASK_TMPDIR/done" ]; then` -- only update manifest if done-file is absent.
**Warning signs:** Completed tasks show `status: abandoned` in manifest.

### Pitfall 5: Heartbeat Threshold Too Aggressive
**From STATE.md blocker:** "3-minute default may be too aggressive for long reasoning steps."
**Resolution:** Phase 4's default MONITOR_BASE_INTERVAL is 30s (down from the old hard-coded 180s), but the staleness threshold is `3 * MONITOR_BASE_INTERVAL = 90s` before even entering grace period, then `MONITOR_GRACE_PERIOD = 30s` before acting. Total: 120s minimum before any action on stale output. Plus, the STALE_SINCE window means the first stale detection is silent -- action only on grace period expiry.
**Configurable path:** Operators can set `MONITOR_BASE_INTERVAL=120` for more conservative hang detection (staleness threshold becomes 360s). This addresses the concern without hard-coding.

### Pitfall 6: 2^RETRY_COUNT Integer Overflow
**What goes wrong:** `$(( BASE * (2 ** RETRY_COUNT) ))` -- bash uses 64-bit integers, but at RETRY_COUNT=60+, `2^60` overflows. For a 5h deadline with 30s base and doubling, RETRY_COUNT will hit the MAX cap after ~3-4 iterations (240s > MAX=300), so overflow is not a practical concern.
**How to avoid:** The interval cap (`MONITOR_MAX_INTERVAL`) effectively caps RETRY_COUNT impact after ~3 doublings from the base. No extra protection needed, but add a comment.

## Code Examples

Verified patterns:

### Complete get_mtime Helper

```bash
# get_mtime: cross-platform file mtime in epoch seconds
# Usage: MTIME=$(get_mtime "$file")
# Returns 0 if file does not exist or stat fails (treated as infinitely old)
get_mtime() {
  local file="$1"
  stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0
}
```

Source: Verified on macOS darwin 25.3.0 -- `stat -f %m /etc/hosts` returns epoch seconds correctly. Linux path verified syntactically (GNU stat uses `-c %Y`).

### Env Var Configuration Block

```bash
# Configurable intervals (override via environment)
MONITOR_BASE_INTERVAL="${MONITOR_BASE_INTERVAL:-30}"
MONITOR_MAX_INTERVAL="${MONITOR_MAX_INTERVAL:-300}"
MONITOR_DEADLINE="${MONITOR_DEADLINE:-18000}"
MONITOR_GRACE_PERIOD="${MONITOR_GRACE_PERIOD:-30}"
```

Source: Verified -- bash `${VAR:-default}` works in bash 3.2+.

### Manifest Crash Update

```bash
# Inside monitor loop on crash detection
RETRY_COUNT=$(( RETRY_COUNT + 1 ))
jq \
  --arg status "crashed" \
  --argjson retry_count "$RETRY_COUNT" \
  --arg last_checked_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '. + {status: $status, retry_count: $retry_count, last_checked_at: $last_checked_at}' \
  "$TASK_TMPDIR/manifest.json" \
  > "$TASK_TMPDIR/manifest.json.tmp" \
  && mv "$TASK_TMPDIR/manifest.json.tmp" "$TASK_TMPDIR/manifest.json"
```

Source: Verified -- jq merge produces correct JSON with `status: "crashed"`, preserves all existing fields. See verification output above.

### EXIT Trap (Cleanup + Abandoned Notification)

```bash
cleanup() {
  # Guard: only update manifest if task not already completed
  if [ -f "$TASK_TMPDIR/manifest.json" ] && [ ! -f "$TASK_TMPDIR/done" ]; then
    jq \
      --arg status "abandoned" \
      --arg abandoned_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '. + {status: $status, abandoned_at: $abandoned_at}' \
      "$TASK_TMPDIR/manifest.json" \
      > "$TASK_TMPDIR/manifest.json.tmp" \
      && mv "$TASK_TMPDIR/manifest.json.tmp" "$TASK_TMPDIR/manifest.json"
    openclaw system event --text "Task abandoned: $SESSION" --mode now
  fi
  tmux pipe-pane -t "$SESSION" 2>/dev/null || true
  tmux kill-session -t "$SESSION" 2>/dev/null || true
}
trap cleanup EXIT
```

Source: EXIT trap verified -- fires on `exit 0`, `exit 1`, script end. `|| true` prevents trap failure on missing session. See trap_test.sh verification above.

### Staleness Check Core Logic

```bash
if [ -f "$TASK_TMPDIR/output.log" ]; then
  OUTPUT_MTIME=$(get_mtime "$TASK_TMPDIR/output.log")
  NOW_TS="$(date +%s)"
  OUTPUT_AGE=$(( NOW_TS - OUTPUT_MTIME ))
  STALENESS_THRESHOLD=$(( MONITOR_BASE_INTERVAL * 3 ))

  if [ "$OUTPUT_AGE" -gt "$STALENESS_THRESHOLD" ]; then
    if [ -z "$STALE_SINCE" ]; then
      STALE_SINCE="$NOW_TS"
      echo "Output stale (${OUTPUT_AGE}s > ${STALENESS_THRESHOLD}s). Grace period started."
    else
      GRACE_ELAPSED=$(( NOW_TS - STALE_SINCE ))
      if [ "$GRACE_ELAPSED" -ge "$MONITOR_GRACE_PERIOD" ]; then
        echo "Grace period expired after ${GRACE_ELAPSED}s. Treating as hang -- resuming."
        STALE_SINCE=""
        RETRY_COUNT=$(( RETRY_COUNT + 1 ))
        # [manifest update + claude -c dispatch]
      fi
    fi
  else
    # Fresh output -- reset stale state
    STALE_SINCE=""
  fi
fi
```

Source: Synthesized from PITFALLS.md P12 (grace period), P6 (heartbeat staleness), REQUIREMENTS.md D-1, STATE.md blocker (threshold tuning).

## State of the Art

| Old Approach (Phase 2) | New Approach (Phase 4) | Impact |
|------------------------|------------------------|--------|
| Hard-coded 180s base interval | `MONITOR_BASE_INTERVAL` env var (default 30s) | Operators can tune without editing script |
| Hard-coded 5h deadline | `MONITOR_DEADLINE` env var (default 5h) | Configurable per deployment |
| No hang detection (only PID liveness) | output.log mtime staleness with grace period | Detects hung-but-alive processes |
| No manifest updates from monitor | jq merge writes `status: crashed/abandoned`, `retry_count`, `last_checked_at` | Brain can query manifest for task health |
| No cleanup on deadline | EXIT trap: disable pipe-pane, kill-session, update manifest | Clean resource management |
| No deadline notification | `openclaw system event` on abandoned | Brain receives notification when task is abandoned |
| 10s grace period after resume (Phase 2 temp fix) | Explicit STALE_SINCE tracking + MONITOR_GRACE_PERIOD | Principled grace period, configurable |

## Open Questions

1. **MONITOR_GRACE_PERIOD as its own env var vs derived from MONITOR_BASE_INTERVAL**
   - What we know: Success criteria says "grace period (default 30s)" -- this is a separate concept from MONITOR_BASE_INTERVAL (default 30s as well). Coincidence in defaults.
   - What's unclear: Should MONITOR_GRACE_PERIOD be its own env var or always be `1 * MONITOR_BASE_INTERVAL`? Making it separate is more explicit; tying it to BASE means fewer knobs.
   - Recommendation: Make it a separate env var (`MONITOR_GRACE_PERIOD`, default 30s) for clarity. Planner should choose one approach.

2. **Staleness threshold value**
   - What we know: STATE.md blocker notes "3-minute default may be too aggressive." The success criteria specifies grace period = 30s, not the staleness detection threshold. The threshold determines when the grace period starts.
   - What's unclear: Should staleness threshold be its own env var (e.g., `MONITOR_STALE_THRESHOLD`) or derived from `MONITOR_BASE_INTERVAL`?
   - Recommendation: Derive from BASE (e.g., `3 * MONITOR_BASE_INTERVAL`) so it scales automatically when BASE is changed. Document this derivation clearly. With default BASE=30s, threshold=90s total detection time + 30s grace = 120s before any action.

3. **PID staleness after resume -- is it fully solved?**
   - What we know: Phase 2 deferred this. The resume via `claude -c` creates a new Claude process but the PID file still contains the old PID. The new Claude process's PID file will only be updated if the shell wrapper re-runs -- but `claude -c` runs inside the tmux pane's existing shell, not as a new wrapper invocation.
   - What's unclear: Whether the resumed `claude -c` process eventually updates the PID file (it doesn't -- the wrapper already exited). This means after resume, every PID check will find the old PID dead, trigger another "crash detected", and issue another resume.
   - Recommendation: Accept this limitation for Phase 4. The retry count provides a bounded loop. Document it. Phase 4's success criteria does not require solving the PID staleness problem, only that "the monitor dispatches `claude --resume`" (i.e., issues the resume command). The rapid-retry risk is mitigated by MONITOR_MAX_INTERVAL capping sleep intervals. Flag as potential Phase 5 work.

## Sources

### Primary (HIGH confidence)

- `/Users/matt/Documents/bluehelixlab/resilient-coding-agent-skill/scripts/monitor.sh` -- Current 89-line monitor; Phase 4 rewrites this
- `/Users/matt/Documents/bluehelixlab/resilient-coding-agent-skill/SKILL.md` -- Current 255-line skill document; Phase 4 may add env var documentation
- `/Users/matt/Documents/bluehelixlab/resilient-coding-agent-skill/.planning/phases/02-detection-infrastructure/02-RESEARCH.md` -- Established patterns: kill -0, done-file priority, ANSI stripping
- `/Users/matt/Documents/bluehelixlab/resilient-coding-agent-skill/.planning/phases/03-structured-state/03-RESEARCH.md` -- Established patterns: jq merge, atomic write, manifest lifecycle
- `/Users/matt/Documents/bluehelixlab/resilient-coding-agent-skill/.planning/STATE.md` -- Known blockers: stat portability, heartbeat threshold tuning
- `/Users/matt/Documents/bluehelixlab/resilient-coding-agent-skill/.planning/REQUIREMENTS.md` -- D-1, D-3, D-6, D-7 specifications
- `/Users/matt/Documents/bluehelixlab/resilient-coding-agent-skill/.planning/research/PITFALLS.md` -- P6 (heartbeat/stat), P9 (EXIT trap), P12 (grace period, done-file race), P14 (loop drift)
- `/Users/matt/Documents/bluehelixlab/resilient-coding-agent-skill/.planning/research/STACK.md` -- Decision 6 (hang detection via output.log mtime)
- Direct verification: `stat -f %m /etc/hosts` on macOS darwin 25.3.0 -- mtime in epoch seconds confirmed
- Direct verification: `trap cleanup EXIT` pattern -- fires on all exit paths confirmed
- Direct verification: jq `. + {status: "crashed", ...}` merge -- preserves existing fields, adds new fields confirmed
- Direct verification: `${VAR:-default}` and exponential backoff arithmetic in bash -- all confirmed working
- Claude CLI `--help` output -- confirms `-c`/`--continue` is the established resume flag; `-r`/`--resume` takes session ID

### Secondary (MEDIUM confidence)

- PITFALLS.md P6 -- macOS `stat -f %m` vs Linux `stat -c %Y` difference; verified on macOS side only in this session
- STACK.md Decision 6 -- output.log mtime as implicit heartbeat: "measures real progress, not synthetic liveness"

### Tertiary (LOW confidence)

- PID staleness after resume behavior -- inferred from code structure; would require live testing to confirm exact behavior

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All tools verified on system; no new dependencies
- Architecture: HIGH -- All patterns tested and verified in shell; loop structure derived from existing Phase 2/3 patterns
- Pitfalls: HIGH -- All pitfalls documented from verified project research (PITFALLS.md) and live testing
- stat portability: HIGH for macOS side (verified); MEDIUM for Linux side (verified syntactically, not on Linux machine)
- PID staleness resolution: LOW -- Behavior after resume requires live testing to confirm

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (bash, jq, and tmux APIs are extremely stable; 30-day validity is conservative)
