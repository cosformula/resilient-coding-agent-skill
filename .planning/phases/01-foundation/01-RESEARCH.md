# Phase 1: Foundation - Research

**Researched:** 2026-02-18
**Domain:** SKILL.md rewrite (single-agent, model-aware, scope claiming) + monitor.sh simplification + task directory schema specification
**Confidence:** HIGH

## Summary

Phase 1 is primarily a deletion and documentation phase. The existing codebase supports four coding agents (Codex, Claude Code, OpenCode, Pi) with agent-type branching in both SKILL.md and monitor.sh. Since the Muscles architecture uses Claude Code exclusively, all non-Claude-Code code paths are dead code. Phase 1 removes them, rewrites the scope claim to be aggressive ("delegate ALL non-chat tasks"), adds model routing via the `--model` flag, preserves the existing secure temp directory and file-based prompt patterns, and documents the canonical task directory layout as a specification.

The technical risk is low -- this phase involves removing code (not adding it), rewriting documentation, and adding a single CLI flag (`--model`) to an existing tmux send-keys template. The critical knowledge gaps are around Claude Code CLI syntax (verified below), model alias behavior, and the exact session resume command syntax (which has changed from `claude --resume` to `claude -r <session-id>` or `claude -c`).

**Primary recommendation:** Execute this phase as two plans: (1) SKILL.md rewrite with model routing and scope claiming, and (2) monitor.sh simplification with agent-type branch removal. The task directory schema specification can live in either plan but should be finalized first since it establishes conventions all subsequent phases build on.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TS-9 | Claude Code only -- Remove all Codex, OpenCode, Pi code paths from SKILL.md and monitor.sh | Verified: SKILL.md has 4 agent sections (lines 39-90), monitor.sh has case branches for 4 agents (lines 25-27, 83-111). All non-Claude paths are dead code. Deletion targets clearly identified. |
| TS-10 | Aggressive scope claiming -- SKILL.md claims ALL non-chat tasks; no duration threshold | Verified: Current SKILL.md says "more than 5 minutes" (line 31) and "For quick tasks under 5 minutes, running the agent directly is fine" (line 35). Both must be replaced with unconditional delegation language. |
| TS-5 | Model routing -- Brain passes opus or sonnet; skill maps to --model claude-opus-4-6 or --model claude-sonnet-4-6 | Verified via official docs: `claude --model opus` and `claude --model sonnet` work as aliases. Full names `claude-opus-4-6` and `claude-sonnet-4-6` also work. The `--model` flag combines with `-p` flag. See "Claude Code CLI --model Flag" section. |
| TS-7 | Secure temp directory management -- Standardize mktemp -d + chmod 700 directory with canonical file layout | Verified: Existing pattern in SKILL.md is correct. Phase 1 extends this by documenting the full canonical file layout (prompt, pid, output.log, manifest.json, done, exit_code) as a specification, even though some files are not yet created until later phases. |
| TS-8 | File-based prompt delivery -- Preserve existing write-to-file pattern; never interpolate prompts into shell commands | Verified: Existing pattern (`"$(cat $TASK_TMPDIR/prompt)"` inside double quotes) is correct and must be preserved. No changes needed -- just ensure it is not regressed during SKILL.md rewrite. |
| D-4 | Task state directory convention -- Canonical layout documented: prompt, pid, output.log, manifest.json, done, exit_code | This is the specification layer over TS-7. Phase 1 documents the convention; later phases implement the files. The specification must include file purposes, ownership (who writes, who reads), and lifecycle. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Claude Code CLI | Latest | Coding agent execution in tmux sessions | Only supported agent; `--model` flag for model routing; `-p` for non-interactive mode |
| tmux | 2.6+ | Process isolation and session management | Already in place; pipe-pane -o requires 2.1+; format strings stable from 2.6+ |
| bash | 4+ | Monitor script and task wrapper | Existing; all operations are native shell primitives |
| jq | Latest | JSON manifest creation/updates (future phases) | Not needed in Phase 1, but the manifest schema should be designed with jq-friendly patterns |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| mktemp | System | Secure temp directory creation | Every task startup; `mktemp -d` + `chmod 700` |
| grep -E | System | Input validation (session names, model param) | Startup validation before tmux commands |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `--model claude-opus-4-6` (full name) | `--model opus` (alias) | Aliases auto-update to latest version; full names pin to specific version. Use full names for determinism. |
| `claude -c` (continue) | `claude -r <session-id>` (resume by ID) | `-c` resumes most recent session in directory; `-r` targets specific session. For crash recovery, `-c` is simpler since we operate within a tmux session where the most recent conversation IS the one that crashed. |

## Architecture Patterns

### Recommended SKILL.md Structure (Post-Phase-1)

```
SKILL.md
  Frontmatter (name, description, metadata)
  Introduction (single agent: Claude Code only)
  Placeholders (<task-name>, <project-dir>, <model>)
  Temp Directory and Prompt Safety
  When to Use (ALL non-chat tasks, no threshold)
  Task Directory Schema (canonical layout spec)
  Start a Task (Claude Code only, with --model)
  Monitor Progress (tmux capture-pane)
  Health Monitoring (reference to monitor.sh)
  Recovery After Interruption (claude -c)
  Cleanup
  Naming Convention
  Checklist
  Limitations
```

### Pattern 1: Model Routing via --model Flag

**What:** The Brain passes a `<model>` placeholder (value: `opus` or `sonnet`). The skill maps this to the Claude Code CLI `--model` flag in the tmux send-keys command.

**When to use:** Every task launch. The Brain always specifies a model tier.

**Example (verified from official Claude Code CLI docs):**
```bash
# Source: https://code.claude.com/docs/en/cli-reference
# The --model flag accepts aliases (opus, sonnet) or full names (claude-opus-4-6)

# Using full model names for determinism:
tmux send-keys -t claude-<task-name> \
  'cd <project-dir> && claude -p --model claude-opus-4-6 "$(cat $TASK_TMPDIR/prompt)" && echo "__TASK_DONE__"' Enter

# Using aliases (auto-resolves to latest version):
tmux send-keys -t claude-<task-name> \
  'cd <project-dir> && claude -p --model opus "$(cat $TASK_TMPDIR/prompt)" && echo "__TASK_DONE__"' Enter
```

**Decision:** Use full model names (`claude-opus-4-6`, `claude-sonnet-4-6`) in the SKILL.md template for determinism. The Brain passes `opus` or `sonnet` as a `<model>` placeholder; the SKILL.md template maps these to full names in the send-keys command. This avoids surprise behavior if Anthropic releases a new model version and the alias silently updates.

### Pattern 2: Aggressive Scope Claiming

**What:** SKILL.md "When to Use" section explicitly claims ALL non-chat tasks with no duration threshold. Uses authoritative language to override the Brain's natural bias toward handling tasks itself.

**When to use:** Always. This is the entire point of the Muscles architecture.

**Example language:**
```markdown
## When to Use This

Use this skill for ALL tasks that are not pure conversational chat. This includes:
- Coding, debugging, refactoring, and architecture work
- File exploration, search, and analysis
- Test writing and test debugging
- Documentation generation
- Code review and security analysis
- Any reasoning or investigation task

You are NOT a coding agent. Do not attempt to do coding work directly.
Delegate ALL substantive work through this skill, regardless of expected duration.
```

### Pattern 3: Session Resume Command (Updated)

**What:** The current monitor.sh uses `claude --resume` which is outdated. The current Claude Code CLI uses `claude -c` (continue most recent session in current directory) or `claude -r <session-id>` (resume specific session by ID).

**When to use:** When the monitor detects a crash and needs to resume the Claude Code session.

**Example (verified from official Claude Code CLI docs):**
```bash
# Source: https://code.claude.com/docs/en/cli-reference
# -c / --continue: Load the most recent conversation in the current directory
# -r / --resume: Resume a specific session by ID or name

# For crash recovery within a tmux session, -c is simplest:
tmux send-keys -t "$SESSION" 'claude -c' Enter

# Or with explicit session ID (more deterministic):
tmux send-keys -t "$SESSION" "claude -r \"$SESSION_ID\"" Enter
```

**Note for Phase 1:** The monitor.sh currently uses `claude --resume` (line 101). This MUST be updated to `claude -c` or `claude -r <id>`. Since Phase 1 is simplifying monitor.sh, this is the right time to fix the resume command. However, do NOT add session ID tracking infrastructure yet -- that is Phase 2+ work. Use `claude -c` for now.

### Anti-Patterns to Avoid

- **Keeping dead agent branches "just in case":** Every line of Codex/OpenCode/Pi code is maintenance burden. Delete completely; git history preserves everything.
- **Using model aliases in the tmux command template:** Aliases like `--model opus` auto-resolve and could change meaning when Anthropic releases new models. Use full names for determinism.
- **Half-hearted scope claiming:** Phrases like "prefer to delegate" or "when appropriate" leave room for the Brain to bypass the skill. Be absolute: "ALL non-chat tasks."
- **Documenting future files that do not exist yet:** The task directory schema should clearly distinguish "exists now" (prompt) from "will be created in Phase N" (pid, output.log, manifest.json, done, exit_code). The schema is a specification, not a claim about current implementation.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Model name mapping | Custom model name resolution logic | Direct CLI flag `--model claude-opus-4-6` | Claude Code handles all model resolution internally; passing the full name is deterministic |
| JSON in SKILL.md | Inline JSON templates with bash heredocs | Document as specification; implement with jq in Phase 3 | Phase 1 only documents the schema; actual JSON generation is Phase 3 work |
| Session resume | Custom session tracking | `claude -c` (continue most recent) | Claude Code's built-in session persistence handles conversation state |

## Common Pitfalls

### Pitfall 1: Model Flag Not Combined with -p Flag

**What goes wrong:** The `--model` flag must be combined with `-p` for non-interactive mode. If the tmux send-keys command uses `--model` without `-p`, Claude Code enters interactive mode inside tmux, which defeats fire-and-forget execution.

**Why it happens:** The existing SKILL.md uses `claude -p "..."` without `--model`. When adding `--model`, it is easy to accidentally restructure the command and drop `-p`.

**How to avoid:** The canonical command template must always include both flags: `claude -p --model <model-name> "$(cat $TASK_TMPDIR/prompt)"`.

**Warning signs:** Claude Code shows an interactive prompt inside the tmux session instead of executing and exiting.

### Pitfall 2: Frontmatter anyBins Still Lists Dead Agents

**What goes wrong:** The SKILL.md YAML frontmatter (lines 8-9) currently declares `anyBins: [codex, claude, opencode, pi]`. If this is not updated to `bins: [claude]`, the skill metadata will still claim it works with agents that are no longer supported.

**Why it happens:** Frontmatter is easy to overlook during a content rewrite.

**How to avoid:** Update frontmatter first, before rewriting content sections. Change `anyBins: [codex, claude, opencode, pi]` to `bins: [tmux, claude]` (since tmux is also required).

**Warning signs:** ClawHub listing shows support for Codex, OpenCode, Pi.

### Pitfall 3: Resume Command Syntax Has Changed

**What goes wrong:** The current monitor.sh (line 101) uses `claude --resume`. The current Claude Code CLI no longer uses this syntax. The correct flags are `-c` / `--continue` (most recent session) or `-r` / `--resume` with a session ID argument.

**Why it happens:** The CLI has evolved; the codebase was written against an older version.

**How to avoid:** Verify resume behavior against current official docs. For Phase 1 (simplified monitor), use `claude -c` which requires no session ID infrastructure.

**Warning signs:** Resume attempts fail with unrecognized flag errors, or Claude Code opens an interactive session picker instead of resuming.

### Pitfall 4: Description Field Still References Multi-Agent

**What goes wrong:** The SKILL.md frontmatter description (line 3) says "Run long-running coding agents (Codex, Claude Code, etc.)". The README.md description is similar. If not updated, the skill's metadata misrepresents its purpose.

**Why it happens:** Easy to focus on code sections and forget metadata/description fields.

**How to avoid:** Grep for "Codex", "OpenCode", "Pi", "opencode", "pi" across ALL files in the repository after edits. This should return zero results outside of git history and planning docs.

**Warning signs:** npm/ClawHub package description mentions unsupported agents.

### Pitfall 5: Existing __TASK_DONE__ Marker in Phase 1

**What goes wrong:** Phase 1 is NOT replacing the `__TASK_DONE__` marker with done-file detection (that is Phase 2). But the simplified monitor.sh still needs to detect completion somehow. If the `__TASK_DONE__` marker is accidentally removed from the send-keys template during the SKILL.md rewrite, the monitor loses its only completion signal.

**Why it happens:** Phase 1 removes dead code but must preserve working patterns that are not yet replaced.

**How to avoid:** Keep the `&& echo "__TASK_DONE__"` suffix in the send-keys template. It will be replaced by done-file semantics in Phase 2. The Phase 1 monitor.sh should still grep for this marker.

**Warning signs:** Monitor never detects task completion; tasks appear to run forever.

## Code Examples

### Claude Code CLI Combined Flags (Verified)

```bash
# Source: https://code.claude.com/docs/en/cli-reference
# Non-interactive mode with model selection
claude -p --model claude-opus-4-6 "Your prompt here"
claude -p --model claude-sonnet-4-6 "Your prompt here"

# Model aliases also work (but less deterministic):
claude -p --model opus "Your prompt here"
claude -p --model sonnet "Your prompt here"

# Combined with allowed tools for full automation:
claude -p --model claude-sonnet-4-6 --allowedTools "Bash,Read,Edit" "Your prompt"

# Resume most recent session in current directory:
claude -c

# Resume with a follow-up prompt (SDK/print mode):
claude -c -p "Continue the previous task"

# Resume specific session by ID:
claude -r "session-id-here" "Continue"
```

### Tmux Send-Keys Template (Phase 1 Target)

```bash
# Phase 1 canonical launch command
# <task-name>: sanitized task identifier [a-z0-9-]
# <project-dir>: existing project directory
# <model>: Brain passes opus -> claude-opus-4-6, sonnet -> claude-sonnet-4-6
TMPDIR=$(mktemp -d) && chmod 700 "$TMPDIR"

# Write prompt via orchestrator write tool (no shell)
# File: $TMPDIR/prompt

tmux new-session -d -s claude-<task-name> -e "TASK_TMPDIR=$TMPDIR"
tmux send-keys -t claude-<task-name> \
  'cd <project-dir> && claude -p --model <model-name> "$(cat $TASK_TMPDIR/prompt)" && echo "__TASK_DONE__"' Enter
```

### Monitor.sh Simplified (Phase 1 Target)

```bash
#!/usr/bin/env bash
# Phase 1: Claude Code only -- no agent-type branching
set -uo pipefail

SESSION="${1:?Usage: monitor.sh <tmux-session>}"
# No $2 agent arg -- Claude Code only

# Session name validation (preserved from current)
if ! printf '%s' "$SESSION" | grep -Eq '^[A-Za-z0-9._-]+$'; then
  echo "Invalid session name: $SESSION" >&2
  exit 1
fi

# ... monitoring loop (same structure, but resume is always claude -c) ...

# On crash detection:
echo "Crash detected. Resuming Claude Code (retry #$RETRY_COUNT)"
tmux send-keys -t "$SESSION" 'claude -c' Enter
```

### Task Directory Schema Specification (Phase 1 Deliverable)

```
$TMPDIR/                         # mktemp -d, chmod 700
  prompt                         # Task instructions
                                 #   Written by: orchestrator write tool
                                 #   Read by: Claude Code via $(cat)
                                 #   Created: Phase 1 (existing)

  pid                            # Claude Code child process PID
                                 #   Written by: task wrapper (pgrep)
                                 #   Read by: monitor.sh (kill -0)
                                 #   Created: Phase 2 (TS-1)

  output.log                     # Continuous output capture
                                 #   Written by: tmux pipe-pane
                                 #   Read by: Brain (tail -n 50), monitor (mtime)
                                 #   Created: Phase 2 (TS-3)

  manifest.json                  # Structured task state (JSON)
                                 #   Written by: task wrapper + monitor
                                 #   Read by: Brain
                                 #   Created: Phase 3 (TS-6)

  done                           # Completion marker (presence = complete)
                                 #   Written by: task wrapper on exit
                                 #   Read by: monitor.sh ([ -f done ])
                                 #   Created: Phase 2 (TS-2)

  exit_code                      # Process exit code (numeric string)
                                 #   Written by: task wrapper (echo $?)
                                 #   Read by: monitor.sh, manifest updater
                                 #   Created: Phase 2 (TS-2)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `claude --resume` (no args) | `claude -c` (continue) or `claude -r <id>` (resume by ID) | Claude Code CLI updates 2025-2026 | Monitor resume command must be updated |
| Multi-agent support (Codex, OpenCode, Pi, Claude) | Claude Code only | Project decision (this rewrite) | ~60% of monitor.sh case branches removed |
| "5+ minutes" duration threshold | ALL non-chat tasks | Project decision (this rewrite) | SKILL.md scope claim fundamentally changes |
| Default model only | `--model opus` or `--model sonnet` | Claude Code CLI (available since at least 2025) | Model routing enables cost/quality optimization |
| `--model opus` alias | Full name `claude-opus-4-6` recommended | Claude Code docs recommend pinning for determinism | Aliases auto-update; full names are stable |

**Deprecated/outdated patterns:**
- `claude --resume` without session ID: Use `claude -c` or `claude -r <id>` instead
- `anyBins: [codex, claude, opencode, pi]` in frontmatter: Replace with `bins: [tmux, claude]`
- Agent-type case branches in monitor.sh: Remove entirely; single Claude Code resume path
- "more than 5 minutes" scope threshold: Replace with unconditional delegation

## Open Questions

1. **Model name format: aliases vs full names**
   - What we know: Both `--model opus` and `--model claude-opus-4-6` work. Aliases auto-resolve to latest; full names pin to specific version.
   - What's unclear: Whether the Brain will always send `opus`/`sonnet` strings, or could send full model names. The SKILL.md template needs to handle the `<model>` placeholder mapping.
   - Recommendation: Define the mapping in SKILL.md. Brain sends `opus` or `sonnet`; SKILL.md template maps to `claude-opus-4-6` or `claude-sonnet-4-6`. This keeps the interface simple for the Brain and deterministic for the skill.

2. **Resume command: -c vs -r with session ID**
   - What we know: `claude -c` continues the most recent session in the current working directory. `claude -r <id>` resumes a specific session. In a tmux session where only one Claude Code instance ran, `-c` should reliably find the right session.
   - What's unclear: If Claude Code was run, crashed, and the working directory has other sessions, `-c` might pick the wrong session.
   - Recommendation: Use `claude -c` for Phase 1 simplicity. Phase 2 can add session ID tracking if needed. The tmux session scope (one agent per session) makes `-c` safe enough.

3. **Dangerously skip permissions flag**
   - What we know: `--dangerously-skip-permissions` allows Claude Code to run without prompting for tool permissions. The current SKILL.md does not use this flag. For fire-and-forget tmux execution, permission prompts would block the agent.
   - What's unclear: Whether `-p` mode alone is sufficient to avoid permission prompts, or whether `--dangerously-skip-permissions` is also needed.
   - Recommendation: Research in Phase 2. Phase 1 preserves the current `-p` pattern. If permission prompts cause issues in testing, add `--dangerously-skip-permissions` to the template.

## Sources

### Primary (HIGH confidence)
- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-reference) -- Complete flag reference; `--model`, `-p`, `-c`, `-r` flags verified
- [Claude Code Model Configuration](https://code.claude.com/docs/en/model-config) -- Model aliases (opus, sonnet, haiku), full model names, alias resolution behavior
- [Claude Code Headless/SDK Mode](https://code.claude.com/docs/en/headless) -- Non-interactive `-p` mode, session continuation patterns, `--continue` and `--resume` usage
- Existing codebase: `SKILL.md` (203 lines), `scripts/monitor.sh` (121 lines) -- Current implementation analyzed line-by-line
- `.planning/research/FEATURES.md` -- Phase 1 requirement analysis (TS-5, TS-7, TS-8, TS-9, TS-10, D-4)
- `.planning/research/PITFALLS.md` -- Pitfall mapping (P8, P10, P15 relevant to Phase 1)

### Secondary (MEDIUM confidence)
- [Claude Code Help Center - Model Configuration](https://support.claude.com/en/articles/11940350-claude-code-model-configuration) -- Supplementary model config info
- `.planning/research/STACK.md` -- Technology decision rationale (bash stays, jq for JSON)
- `.planning/research/ARCHITECTURE.md` -- Component boundary definitions

### Tertiary (LOW confidence)
- `--dangerously-skip-permissions` interaction with `-p` mode -- Need empirical validation in Phase 2
- `claude -c` behavior when multiple sessions exist in same directory -- Edge case needs testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All tools verified against official docs; no speculative choices
- Architecture: HIGH -- Deletion and documentation; no novel architecture decisions
- Pitfalls: HIGH -- Concrete issues identified from existing code + verified CLI changes
- Model routing: HIGH -- Verified against official Claude Code CLI reference and model config docs
- Resume command: HIGH -- Verified `claude -c` is the correct replacement for `claude --resume`

**Research date:** 2026-02-18
**Valid until:** 2026-03-18 (30 days -- Claude Code CLI is actively evolving; re-verify if delayed)
