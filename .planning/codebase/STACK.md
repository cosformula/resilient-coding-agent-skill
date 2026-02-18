# Technology Stack

**Analysis Date:** 2026-02-18

## Languages

**Primary:**
- Bash - All operational scripts and task automation

**Documentation:**
- Markdown - Project documentation and skill specification

## Runtime

**Environment:**
- Bash 3.0+ (POSIX-compatible shell)
- `set -uo pipefail` enforced throughout for safety

**System Requirements:**
- `tmux` (required for session management)
- At least one coding agent CLI: `codex`, `claude`, `opencode`, or `pi`
- Optional: `jq` (used for reliable JSON parsing in Codex session ID extraction, with grep fallback)

**Platform Support:**
- macOS / Linux: Fully supported
- Windows: Requires WSL (no native Windows support; tmux unavailable)

## Frameworks

**Build/CI/CD:**
- GitHub Actions (workflows in `.github/workflows/`)
  - `ci.yml` - Package verification and publish directory validation
  - `clawhub-publish.yml` - Skill publishing to ClawHub registry
  - `release.yml` - Release automation

**Package Distribution:**
- ClawHub - Skill registry and distribution platform
- npm CLI (used in CI to install and run `clawhub` command-line tool)

## Key Dependencies

**System Tools (no package manager dependencies):**
- `tmux` - Terminal multiplexer for session management
- `bash` - Shell interpreter
- `grep`, `sed`, `cut`, `date` - Unix utilities (all standard)
- `jq` (optional) - JSON query tool for parsing Codex events
  - Fallback: `grep` extraction if jq unavailable

**Coding Agent CLIs:**
- `codex` - Codex CLI (session-based with `codex exec resume`)
- `claude` - Claude Code command-line (supports `--resume`)
- `opencode` - OpenCode CLI
- `pi` - Pi coding agent

## Configuration

**Environment:**
- `TASK_TMPDIR` - Secure temporary directory passed to tmux session (created with `mktemp -d`)
- `CLAWHUB_TOKEN` - GitHub secret for ClawHub publishing (CI/CD only)

**Secure Temp Directory:**
- Created per-task using `mktemp -d` (produces paths like `/var/folders/xx/.../T/tmp.aBcDeFgH`)
- Permissions set to `700` (owner read/write/execute only)
- Contains:
  - `prompt` - Task prompt file (written by orchestrator)
  - `events.jsonl` - Codex event stream (if using Codex)
  - `codex-session-id` - Codex session ID extracted from events (Codex only)
  - `done` - Completion marker file (optional)

**Build Configuration:**
- `.clawhubignore` - Specifies files excluded from skill publication
  - Excludes: `.git/`, `.github/`, `node_modules/`, build artifacts, test files, scripts directory, README.md

**CI Configuration Files:**
- `.github/workflows/ci.yml` - Verifies publish directory structure
- `.github/workflows/clawhub-publish.yml` - Publishes to ClawHub registry
- `.github/workflows/release.yml` - Automated release workflow

## Security Practices

**Input Sanitization:**
- Session names: Validated to match `[A-Za-z0-9._-]+` only (no special shell characters)
- Codex session IDs: Validated to match `[A-Za-z0-9_-]+` pattern (UUID-like format)
- Prompts: Never interpolated into shell commands; always read from temp files using command substitution in double quotes: `"$(cat $TMPDIR/prompt)"`

**File Safety:**
- Temp directories created with `mktemp -d` (cryptographically secure)
- Permissions set to `700` to prevent unauthorized access on shared machines
- Explicit directory creation avoids symlink races and predictable paths

**Shell Safety:**
- `set -uo pipefail` enforced to fail fast on errors
- No shell eval or dynamic code generation
- Input validation before use in `tmux send-keys` commands

## Platform Requirements

**Development:**
- macOS or Linux system
- `tmux` installed
- At least one coding agent CLI configured and available
- `bash` (3.0+)

**Production/Deployment:**
- Target platform: Agent execution environment (local or remote)
- `tmux` must be installed and accessible
- Coding agent CLIs installed
- GitHub Actions for automated CI/CD and publishing

---

*Stack analysis: 2026-02-18*
