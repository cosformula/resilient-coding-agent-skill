# Testing Patterns

**Analysis Date:** 2026-02-18

## Test Framework

**Runner:**
- No test framework configured
- CI pipeline: GitHub Actions (see `.github/workflows/ci.yml`)
- No JavaScript/TypeScript test runners (Jest, Vitest, etc.) detected
- No shell test framework (BATS, shunit2, etc.) detected

**Assertion Library:**
- Not applicable

**Run Commands:**
```bash
# CI runs this command (see .github/workflows/ci.yml):
rsync -a --delete --exclude-from=.clawhubignore ./ "$OUT/"
echo "Publish files:"; find "$OUT" -type f -maxdepth 3 -print
test ! -f "$OUT/README.md"
test ! -d "$OUT/tests"
test ! -d "$OUT/.github"
test -f "$OUT/SKILL.md"
```

This verifies the publish directory structure using basic POSIX `test` commands (no test framework).

## Test File Organization

**Location:**
- No test files in codebase
- CI explicitly excludes `tests/` directory (`.github/workflows/ci.yml` line 21)

**Naming:**
- Not applicable

**Structure:**
```
[No test directory exists]
```

## Test Structure

**Suite Organization:**
- Not applicable (no test framework present)

**Patterns:**
- Not applicable

## Mocking

**Framework:**
- Not applicable (no test framework)

**Patterns:**
- Manual testing via `tmux` commands (documented in SKILL.md)
- Health monitoring script `scripts/monitor.sh` is testable via tmux session simulation

**What to Mock:**
- tmux session operations (can be mocked by creating test sessions)
- Agent CLI responses (can be mocked by stubbed CLI tools)

**What NOT to Mock:**
- Shell command outputs that affect control flow (e.g., `tmux has-session` exit code)

## Fixtures and Factories

**Test Data:**
- Not applicable (no test framework)
- Manual test data in SKILL.md examples:
  ```bash
  # Example session from README.md (lines 59-66):
  SESSION="codex-refactor"
  TMPDIR=$(mktemp -d) && chmod 700 "$TMPDIR"
  echo "Refactor auth module" > "$TMPDIR/prompt"
  tmux new-session -d -s "$SESSION" -e "TASK_TMPDIR=$TMPDIR"
  ```

**Location:**
- Documentation examples in `SKILL.md` (lines 43-90) and `README.md` (lines 57-87)
- No fixture files committed to repo

## Coverage

**Requirements:**
- None enforced
- No coverage reporting tool configured

**View Coverage:**
- Not applicable

## Test Types

**Unit Tests:**
- Not applicable (no test framework)
- Individual shell script functions could theoretically be unit tested via BATS or shunit2, but not implemented

**Integration Tests:**
- Manual testing via tmux (documented in SKILL.md "Monitor Progress" section, lines 109-118)
- CI verifies publish directory structure (`.github/workflows/ci.yml`)
- No automated integration test suite

**E2E Tests:**
- Not used
- Manual E2E validation documented in README.md "Quick Start" (lines 55-87)

## CI/CD Pipeline

**Pipeline File:** `.github/workflows/ci.yml`

**Jobs:**
1. `package-check` (runs on ubuntu-latest)
   - Verifies the rsync publish directory excludes unnecessary files
   - Checks that `tests/` and `.github/` are not published
   - Confirms `SKILL.md` is included in publish output
   - Uses basic POSIX `test` commands (not a test framework)

**Validation Steps (from ci.yml lines 14-23):**
```bash
# Create clean publish directory
OUT=/tmp/skill
rm -rf "$OUT" && mkdir -p "$OUT"
rsync -a --delete --exclude-from=.clawhubignore ./ "$OUT/"

# List files
echo "Publish files:"; find "$OUT" -type f -maxdepth 3 -print

# Verify constraints
test ! -f "$OUT/README.md"          # README should not be published
test ! -d "$OUT/tests"              # tests/ should not be published
test ! -d "$OUT/.github"            # .github/ should not be published
test -f "$OUT/SKILL.md"             # SKILL.md must be included
```

**Exclude Rules:** `.clawhubignore` file controls what gets published

**Manual Testing Approach:**
- Health monitoring tests should cover:
  1. Session exists but agent still running → no resume
  2. Session crashed (shell prompt detected) → resume triggered
  3. Session crashed (exit indicator detected) → resume triggered
  4. Session disappeared → monitor exits gracefully
  5. Task completed with `__TASK_DONE__` marker → monitor exits normally
  6. Retry backoff: 3m base, doubles on consecutive failures
  7. 5-hour wall-clock deadline stops monitoring

**Test Execution (Manual):**
```bash
# Create a test tmux session
tmux new-session -d -s test-monitor

# Inject test output that looks like a crash
tmux send-keys -t test-monitor "some output" Enter
tmux send-keys -t test-monitor "user@host$ " Enter  # Simulates shell prompt return

# Run monitor
./scripts/monitor.sh test-monitor codex

# Verify monitor detects crash and resumes
tmux capture-pane -t test-monitor -p
```

## Known Testing Gaps

**Shell script testing:**
- No automated tests for `scripts/monitor.sh`
- Critical crash detection logic (lines 70-78) untested
- Retry backoff logic (lines 48, 81, 113) untested
- 5-hour deadline timeout (lines 39, 42-46) untested
- Agent-specific resume commands (lines 83-111) not individually tested

**Integration points untested:**
- Actual tmux session monitoring against real agents
- Session ID file creation and parsing for Codex (lines 85-91)
- Output parsing for shell prompt detection (line 76 regex)

**Recommendation for future testing:**
- Implement BATS (Bash Automated Testing System) test suite
- Create test fixtures for each agent type
- Mock tmux commands in tests using a wrapper script
- Verify crash detection heuristics with sample outputs
- Test retry backoff with time mocking

---

*Testing analysis: 2026-02-18*
