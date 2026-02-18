# Codebase Structure

**Analysis Date:** 2026-02-18

## Directory Layout

```
resilient-coding-agent-skill/
├── .github/                    # CI/CD workflows
│   └── workflows/
├── .planning/                  # GSD planning documents (this directory)
│   └── codebase/
├── scripts/                    # Executable monitoring and utility scripts
│   └── monitor.sh
├── LICENSE                     # MIT license
├── README.md                   # User-facing quick start guide
├── SKILL.md                    # Skill specification and complete usage documentation
├── .clawhubignore              # ClawHub package exclusions
└── .gitignore                  # Git exclusions (excludes scripts/, tests/, etc.)
```

## Directory Purposes

**`.github/`:**
- Purpose: GitHub Actions CI/CD pipeline definitions
- Contains: Workflow YAML files for linting, testing, publishing to ClawHub
- Key files: `workflows/ci.yml`, `workflows/clawhub-publish.yml`

**`.planning/`:**
- Purpose: GSD (Golden Source Design) codebase analysis and phase planning documents
- Contains: Architecture analysis (ARCHITECTURE.md), structure documentation (STRUCTURE.md), conventions, testing patterns, integration catalog, and concerns registry
- Key files: `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STRUCTURE.md`

**`scripts/`:**
- Purpose: Executable shell scripts for runtime operations
- Contains: Health monitoring and recovery logic
- Key files: `scripts/monitor.sh` (health monitor, crash detection, auto-resume)

**Root-level documentation:**
- `SKILL.md`: Complete specification and usage guide for the skill (task startup, monitoring, recovery, cleanup)
- `README.md`: Quick start and feature summary for GitHub/package registry
- `LICENSE`: MIT license grant
- `.clawhubignore`: Package metadata exclusion list (excludes README.md, scripts/, tests/, etc. from published packages)
- `.gitignore`: Git exclusion patterns (node_modules/, build/, .venv/, etc.)

## Key File Locations

**Entry Points:**

- `scripts/monitor.sh`: Executable entry point for health monitoring. Called by background scheduler with arguments `<tmux-session> <agent>`
- `SKILL.md`: Documentation entry point; defines task startup patterns for orchestrators to follow

**Configuration:**

- `.github/workflows/`: CI pipeline configuration (linting, testing, publishing steps)
- `.clawhubignore`: Package registry metadata specifying which files are excluded from published distribution

**Core Logic:**

- `scripts/monitor.sh` (lines 41-121): Main monitoring loop with session health checks, crash detection, and recovery dispatch
- `scripts/monitor.sh` (lines 83-111): Agent-specific resume logic (switch statement for codex|claude|opencode|pi)
- `SKILL.md` (lines 43-90): Task startup patterns for each supported agent CLI

**Testing:**

- No test files committed to repository (listed in `.gitignore` and `.clawhubignore`)
- Tests are present in CI via GitHub Actions (`.github/workflows/`)

## Naming Conventions

**Files:**

- Executable scripts: lowercase with hyphens (`monitor.sh`)
- Documentation: UPPERCASE.md (`README.md`, `SKILL.md`, `ARCHITECTURE.md`)
- Configuration: dot-prefix with hyphens (`.gitignore`, `.clawhubignore`)

**Directories:**

- Hidden directories: dot-prefix (`.github/`, `.planning/`)
- Public directories: lowercase (scripts/, workflows/)

**Tmux Session Names (at runtime):**

- Format: `<agent>-<task-name>` where agent is one of: `codex`, `claude`, `opencode`, `pi`
- Examples: `codex-refactor-auth`, `claude-review-pr-42`, `opencode-analyze-perf`
- Constraint: Lowercase, hyphens, alphanumeric only; validated by regex `^[a-z0-9-]+$` in usage

**Environment Variables (at runtime):**

- `TASK_TMPDIR`: Path to secure temp directory created with `mktemp -d`
- Constraint: Passed via tmux `-e` flag; never interpolated into shell commands

**Files Created at Runtime:**

- `$TMPDIR/prompt`: Task instructions (written by orchestrator)
- `$TMPDIR/events.jsonl`: Agent output log (populated by agent during execution)
- `$TMPDIR/codex-session-id`: Codex thread ID for recovery (extracted from events.jsonl during startup)
- `$TMPDIR/done`: Optional completion marker file (created when task finishes)

## Where to Add New Code

**New Feature (supporting a new agent CLI):**
- Primary code: Add case in `scripts/monitor.sh` lines 83-111 for agent-specific resume logic
- Documentation: Add agent-specific startup pattern to `SKILL.md` following existing examples (lines 43-90)
- Validation: Add agent type to allowed set in line 26 of `scripts/monitor.sh`

**New Monitoring Strategy (e.g., webhook callback):**
- Implementation: Add logic to completion notification section in `SKILL.md` (lines 92-105)
- No code change needed if using tmux-native features (marker files, system events)

**New Agent Support with Native Resume:**
- Primary code: Add case statement in `scripts/monitor.sh` (lines 83-111)
- Example resume command pattern: `<agent> <command> [args]`
- Documentation: Add startup pattern to `SKILL.md` section "Start a Task"

**New Agent Support WITHOUT Native Resume:**
- Primary code: Add case statement in `scripts/monitor.sh` setting `RETRY_COUNT=0` and breaking monitor loop (like Pi, lines 107-110)
- Documentation: Explicitly state in `SKILL.md` that agent lacks resume capability

**Utilities (shared functions):**
- Add to `scripts/monitor.sh` as shell functions (no separate utility files)
- Examples: prompt detection logic (currently inline, lines 70-78), file validation (currently inline, line 88)

**Documentation / Examples:**
- Usage examples: Add to `SKILL.md` following existing agent-specific patterns
- Quick starts: Update `README.md` section "Quick Start" with concrete examples
- Architecture notes: Update `ARCHITECTURE.md` for significant pattern changes

## Special Directories

**`.github/workflows/`:**
- Purpose: GitHub Actions CI configuration
- Generated: No (manually maintained YAML)
- Committed: Yes
- Contains: Linting rules, test execution steps, publishing automation to ClawHub

**`.planning/codebase/`:**
- Purpose: Golden Source Design documentation (architecture, structure, conventions, testing patterns, concerns)
- Generated: No (created by GSD mapping tool, manually reviewed)
- Committed: Yes
- Contains: Analysis documents for future phase planning and code generation guidance

**Runtime temp directories (created at task startup):**
- Pattern: `/var/folders/xx/.../T/tmp.aBcDeFgH` (via `mktemp -d`)
- Generated: Yes (by orchestrator startup routine)
- Committed: No (ephemeral, cleaned up after task)
- Contents: Prompt files, event logs, session IDs, completion markers

---

*Structure analysis: 2026-02-18*
