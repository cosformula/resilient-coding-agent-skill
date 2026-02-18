# Codebase Concerns

**Analysis Date:** 2026-02-18

## Tech Debt

**Shell script robustness:**
- Issue: Monitor script uses string pattern matching to detect shell prompts and exit indicators, which can produce false positives
- Files: `scripts/monitor.sh` (lines 76-78)
- Impact: Agent may be incorrectly detected as crashed when agent output contains strings like `exit code 200` or lines ending with `$ ` in the middle of output
- Fix approach: Improve prompt detection by checking for complete shell context (user@host patterns) or by storing a flag file when the agent starts executing

**Temp file cleanup:**
- Issue: Documentation creates temp directories with `mktemp -d` but provides no automatic cleanup mechanism
- Files: `SKILL.md` (lines 45, 70, 79, 87), `README.md` (lines 60, 71, 80, 88)
- Impact: Long-running monitoring loops could accumulate many temp directories on the file system, consuming disk space
- Fix approach: Document cleanup as a required post-task step; consider adding a cleanup function to scripts/monitor.sh

**Hard-coded 5-hour retry ceiling:**
- Issue: Monitor script has a hard-coded 5-hour wall-clock timeout after which monitoring stops
- Files: `scripts/monitor.sh` (line 39)
- Impact: Tasks running longer than 5 hours will not be automatically recovered if they crash after the deadline
- Fix approach: Make deadline configurable or document expected task duration limits clearly

## Known Limitations

**No reboot resilience:**
- Issue: tmux sessions are lost on machine reboot; the skill cannot recover from reboots
- Files: `SKILL.md` (lines 199-201)
- Workaround: Rely on agent-native resume commands (`codex exec resume <session-id>`, `claude --resume`) after rebooting

**Pi agent has no resume:**
- Issue: Pi coding agent has no native resume mechanism, so crashes cannot be auto-recovered
- Files: `scripts/monitor.sh` (lines 107-109), `SKILL.md` (line 162)
- Workaround: Require manual restart for Pi tasks; document this limitation clearly

**Crash detection false negatives:**
- Issue: If an agent crashes without printing a shell prompt or explicit exit indicator, it will not be detected by the monitor loop
- Files: `scripts/monitor.sh` (lines 70-78)
- Impact: Agent could hang silently while monitor thinks it's still working
- Fix approach: Add heartbeat/output monitoring (e.g., timestamp of last output line) to detect stalls

## Security Considerations

**Temp file secrets exposure:**
- Risk: Task prompts, event logs, and output written to temp files may contain API keys, credentials, or sensitive data
- Files: `SKILL.md` (lines 18, 22, 49-53, 70-90)
- Current mitigation: Documentation recommends `chmod 700` for temp directories (line 46) and warns about shared machines (line 22)
- Recommendations:
  - Add explicit file mode guidance for each sensitive file type (e.g., `chmod 600` for event logs)
  - Document cleanup of temp files as a security best practice
  - Consider adding a cleanup script that securely removes temp directories

**Codex session ID validation:**
- Risk: Session ID is read from a file and passed to shell command; weak validation could allow injection
- Files: `scripts/monitor.sh` (lines 86-91)
- Current mitigation: Session ID format validated with regex `^[A-Za-z0-9_-]+$` before use
- Recommendations: This is adequate for the current approach, but document why this specific format is safe

**TMux session name validation:**
- Risk: Session name could be used in shell injection if not properly validated
- Files: `scripts/monitor.sh` (lines 31-34)
- Current mitigation: Session name validated with regex `^[A-Za-z0-9._-]+$`
- Recommendations: Current validation is good; maintain this pattern for all user inputs

## Performance Bottlenecks

**Monitor polling interval:**
- Problem: Default monitoring interval is 3 minutes (180 seconds), which means crashes could go undetected for up to 3 minutes
- Files: `scripts/monitor.sh` (lines 114, 180)
- Impact: User could experience delayed notification of task completion or crash
- Improvement path: Allow configurable polling interval, or implement faster detection via inotify/fswatch on completion marker file

**Exponential backoff ceiling:**
- Problem: Backoff doubles indefinitely (3m, 6m, 12m, 24m, ...) until 5h deadline, meaning very long gaps between retries
- Files: `scripts/monitor.sh` (lines 48, 51-54)
- Impact: Failed tasks may not be retried frequently, especially if intermittent failures occur
- Improvement path: Implement maximum backoff interval (e.g., cap at 30 minutes) to ensure minimum retry frequency

## Fragile Areas

**Prompt safety assumptions:**
- Files: `SKILL.md` (lines 20-21)
- Why fragile: Documentation assumes orchestrator uses a "write" tool that does not invoke a shell, but does not verify this at runtime
- Safe modification: Always document that prompt must be written to a file first; never interpolate prompts into shell commands
- Test coverage: No automated tests verify the safety of prompt handling

**Shell prompt detection logic:**
- Files: `scripts/monitor.sh` (lines 75-78)
- Why fragile: Uses simple regex patterns to detect shell prompts; can match agent output that includes `$ `, `% `, or `> ` mid-line
- Safe modification: Add more context to detection (user@host, newline boundaries) or use timestamp-based activity detection
- Test coverage: No test cases for edge cases like "HTTP status 200" or log lines ending with `$ `

**Codex session ID extraction:**
- Files: `SKILL.md` (lines 56-64)
- Why fragile: Depends on jq being available; falls back to grep with hard-coded JSON format
- Safe modification: Make the jq fallback more robust by testing both branches; document when each is used
- Test coverage: No tests verify session ID extraction under various event log formats

## Dependency Risks

**External tool dependencies:**
- Risk: Script depends on `tmux`, `jq` (or grep fallback), and agent CLIs (codex, claude, opencode, pi)
- Files: `SKILL.md` (lines 8-9), `scripts/monitor.sh` (lines 58-62)
- Impact: Script fails to initialize if tmux is not installed; session ID extraction fails if jq is not available and grep pattern doesn't match
- Migration plan: Document all required dependencies; consider bundling jq or using POSIX shell alternatives

## Scaling Limits

**Monitor process overhead:**
- Current capacity: One monitor process per task; polling every 3-300+ seconds depending on retry count
- Limit: Orchestrator that runs 100+ concurrent tasks would spawn 100+ monitor processes consuming memory/CPU
- Scaling path: Implement a centralized monitor that watches multiple tasks via configuration file or message queue

**Temp directory accumulation:**
- Current capacity: Each task creates one temp directory; no documented cleanup
- Limit: Long-running orchestrator could accumulate thousands of temp directories in /tmp
- Scaling path: Add automatic cleanup (e.g., cron job to remove temp directories older than 24 hours) or garbage collection in the script

## Missing Critical Features

**Output capture to file:**
- Problem: `scripts/monitor.sh` captures output via `tmux capture-pane` but does not save it to a persistent file
- Blocks: User cannot access full task output after task completes (only scrollback is available while session exists)
- Recommendation: Automatically pipe agent output to a log file in the temp directory for post-task review

**Task completion metadata:**
- Problem: No structured way to record task completion status, exit code, or final output
- Blocks: Orchestrator cannot programmatically determine if task succeeded or failed
- Recommendation: Write a completion manifest file (JSON) with task status, exit code, completion time, and output location

**Retry exhaustion handling:**
- Problem: Monitor silently stops after 5 hours without notifying user that retries are exhausted
- Blocks: User doesn't know if task is dead or still running after deadline
- Recommendation: Write status to a file or send a notification when retry timeout is reached

## Test Coverage Gaps

**No automated tests:**
- What's not tested: Shell script functions, prompt escaping, crash detection logic, session ID parsing
- Files: No test directory present; `tests/` is excluded from published package (`.clawhubignore`)
- Risk: Regressions in monitor.sh could break crash detection without warning
- Priority: High - Add shell script unit tests (using bats or similar) for critical functions

**Crash detection accuracy:**
- What's not tested: False positive rate of prompt detection, edge cases like multi-line output with `$ ` in middle
- Files: `scripts/monitor.sh` (lines 75-78)
- Risk: Agent could be incorrectly restarted or missed crashes could go undetected
- Priority: High - Add test cases covering common log formats (HTTP status, Python tracebacks, etc.)

**Session ID extraction robustness:**
- What's not tested: Codex event log parsing with jq fallback, session ID validation edge cases
- Files: `SKILL.md` (lines 56-64), `scripts/monitor.sh` (lines 86-91)
- Risk: Session ID could be extracted incorrectly or validation could fail on valid IDs
- Priority: Medium - Add tests for various event log formats and edge cases

**Integration with agent CLIs:**
- What's not tested: Resume commands for each agent (codex, claude, opencode)
- Files: `scripts/monitor.sh` (lines 83-111)
- Risk: Resume commands could fail or have different behavior in new agent versions
- Priority: Medium - Document and test resume behavior with each agent

---

*Concerns audit: 2026-02-18*
