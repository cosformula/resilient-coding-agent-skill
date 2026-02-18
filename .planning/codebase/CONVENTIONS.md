# Coding Conventions

**Analysis Date:** 2026-02-18

## Naming Patterns

**Files:**
- Markdown documentation: `UPPERCASE.md` for main docs (e.g., `SKILL.md`, `README.md`)
- Shell scripts: lowercase with `.sh` extension (e.g., `monitor.sh`)
- Configuration: use standard names (`.clawhubignore`, `.gitignore`, `.github/workflows/`)
- GitHub Actions: `[purpose].yml` in `.github/workflows/` (e.g., `ci.yml`, `clawhub-publish.yml`)

**Functions:**
- Bash functions use snake_case (no bash functions present; scripts are procedural)
- Variable names in bash: UPPERCASE for constants and environment variables (e.g., `SESSION`, `AGENT`, `TMPDIR`, `RETRY_COUNT`, `START_TS`, `DEADLINE_TS`)
- Local variables: lowercase for temporary/iterative values (e.g., `output`, `recent`, `interval`)

**Variables:**
- Environment variables: UPPERCASE with underscores (e.g., `TASK_TMPDIR`, `CODEX_SESSION_FILE`)
- Local bash variables: lowercase (e.g., `session`, `agent`, `retry_count`)
- Derived paths: descriptive with underscores (e.g., `CODEX_SESSION_FILE="/tmp/${SESSION}.codex-session-id"`)

**Types:**
- Not applicable (shell script codebase, no type system)

## Code Style

**Formatting:**
- Shell scripts use explicit shebang: `#!/usr/bin/env bash`
- Set strict mode at top of scripts: `set -uo pipefail` (see `scripts/monitor.sh` line 19)
- Use 2-space indentation (consistent throughout `scripts/monitor.sh`)
- Line length: no strict limit observed, but lines wrapped pragmatically for readability

**Linting:**
- No linting tool configured (ShellCheck not detected)
- Shell scripts follow POSIX-compatible patterns where possible
- Command substitution uses `$()` not backticks (see `scripts/monitor.sh` line 21: `"${1:?Usage: ...}"`)

**Error Handling Style:**
- Bash parameter expansion with error defaults: `"${1:?Usage: ...}"` (line 21-22)
- Explicit exit codes on validation: `exit 1` after error messages
- Error messages go to stderr: `>&2` (e.g., line 32, 33)
- Condition checks use early exit pattern: check prerequisites first, fail fast

## Import Organization

**Not applicable** - This is a shell script and markdown documentation codebase with no imports or module system.

**File sourcing:** No sourcing observed. Each script is standalone.

## Error Handling

**Patterns:**

1. **Parameter validation (immediate):**
   ```bash
   SESSION="${1:?Usage: monitor.sh <tmux-session> <agent>}"
   AGENT="${2:?Usage: monitor.sh <tmux-session> <agent>}"
   ```
   Fail immediately if required args missing.

2. **Enumeration validation (case statement):**
   ```bash
   case "$AGENT" in
     codex|claude|opencode|pi) ;;
     *) echo "Unsupported agent: $AGENT ..." >&2; exit 1 ;;
   esac
   ```
   See `scripts/monitor.sh` lines 25-28.

3. **Input sanitization (regex validation):**
   ```bash
   if ! printf '%s' "$SESSION" | grep -Eq '^[A-Za-z0-9._-]+$'; then
     echo "Invalid session name: $SESSION ..." >&2
     exit 1
   fi
   ```
   Validate strings before using in commands. See lines 31-34.

4. **Graceful command failure (with fallback):**
   ```bash
   OUTPUT="$(tmux capture-pane -t "$SESSION" -p -S -120 2>/dev/null)" || {
     echo "tmux session $SESSION disappeared during capture. Stopping monitor."
     break
   }
   ```
   Use `|| { ... }` to handle command failures. See lines 59-62.

5. **Non-fatal warnings:**
   - Echo to stdout/stderr as appropriate
   - Continue execution where possible (e.g., session disappears during monitoring, exit gracefully)

## Logging

**Framework:** Bash `echo` and `printf`

**Patterns:**

1. **Status messages (informational):** `echo "Task completed normally."` (line 66)
2. **Error messages:** To stderr with `>&2` (line 32, 33)
3. **Progress tracking:** Echo diagnostic info (lines 92, 100, 104) showing agent and retry count
4. **Timestamps:** Use `date +%s` for Unix timestamps (lines 38, 42), not human-readable

**When to log:**
- Agent state changes (detected crash, resumed task)
- Validation failures (invalid input)
- Timeout events (5h deadline reached)
- Session state (session exists/missing)
- Do NOT log secrets or full command lines that may contain sensitive data

## Comments

**When to Comment:**

- Top-of-file shebang and usage doc (see `scripts/monitor.sh` lines 1-17)
- Algorithm intent for complex logic (lines 70-78 explain prompt detection heuristics)
- Non-obvious regex patterns (line 76 comment explains why it matches bare prompts only, line 88 validates session ID format)

**Style:**
- Inline comments preceded by `#` (see line 13, 70, 87)
- Multi-line blocks use `# Line of comment` style (not `/\* ... \*/`)
- Markdown headers in SKILL.md and README.md use standard Markdown (##, ###, etc.)

**JSDoc/TSDoc:**
- Not applicable (no JavaScript/TypeScript in codebase)

## Function Design

**Size:**
- Scripts are procedural, not function-based
- `scripts/monitor.sh` is ~120 lines of linear logic with one main loop

**Parameters:**
- Script arguments validated upfront with `${variable:?error message}` pattern
- No function parameters (no functions defined)
- Positional arguments: `$1` (session name), `$2` (agent type)

**Return Values:**
- Scripts exit with 0 on success, 1 on error
- Variables set via command substitution: `$(command)` (lines 21, 38, 42)
- No explicit return statements

## Module Design

**Exports:**
- Markdown files are documentation, not code modules
- Bash scripts are CLI tools, not modules
- No barrel files or re-exports

**Barrel Files:**
- Not applicable

## Special Patterns

**Arithmetic in Bash:**
- Use `$(( ... ))` syntax for arithmetic (lines 39, 48, 51, 81)
- Example: `DEADLINE_TS=$(( START_TS + 18000 ))` (line 39)

**String Handling:**
- Use double quotes for variable interpolation: `"$VARIABLE"`
- Use single quotes to prevent interpolation
- Use `printf '%s\n'` for safe output (line 75)

**Conditional Logic:**
- Prefer explicit conditions: `-z` for empty, `-s` for file exists and non-empty (line 57: `[ -s "$CODEX_SESSION_FILE" ]`)
- Use `-eq` / `-ne` for numeric comparison (lines 80, 113)
- Use `grep -E` for extended regex (line 31)

---

*Convention analysis: 2026-02-18*
