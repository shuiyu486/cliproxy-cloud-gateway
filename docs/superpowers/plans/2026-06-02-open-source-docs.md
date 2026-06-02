# Open Source Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare cliproxy-cloud-gateway for open-source publication with a Chinese default README, English README, maintainable project memory, and GitHub publishing checks.

**Architecture:** Documentation stays project-native and static. The Chinese README is the default entry point, `README.en-US.md` mirrors it for English readers, and `CLAUDE.md` routes future maintainers to only the context they need.

**Tech Stack:** Markdown, Mermaid, PowerShell regression tests, Git/GitHub CLI when available.

---

### Task 1: Documentation Tests

**Files:**
- Modify: `tests/Test-CloudGateway.ps1`

- [ ] **Step 1: Write failing README and memory assertions**

Add assertions for `README.en-US.md`, `CLAUDE.md`, language switch links,
Mermaid flowcharts, open-source usage sections, and memory routing headings.

- [ ] **Step 2: Run tests and verify RED**

Run: `.\tests\Test-CloudGateway.ps1`

Expected: FAIL because `README.en-US.md` and `CLAUDE.md` do not exist and the current default README is not Chinese.

### Task 2: Bilingual README

**Files:**
- Modify: `README.md`
- Create: `README.en-US.md`

- [ ] **Step 1: Rewrite default README in Chinese**

Include the project purpose, flowchart, quick start, upstream proxy explanation,
doctor checks, security defaults, troubleshooting, and GitHub release note.

- [ ] **Step 2: Add English README**

Mirror the Chinese README structure in English and link back to `README.md`.

- [ ] **Step 3: Run tests**

Run: `.\tests\Test-CloudGateway.ps1`

Expected: only `CLAUDE.md` assertions still fail until Task 3 is done.

### Task 3: Maintenance Memory

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Add progressive-disclosure memory**

Create a concise routing table, architecture boundaries, non-breaking contracts,
config contracts, testing requirements, and GitHub release checklist.

- [ ] **Step 2: Run tests**

Run: `.\tests\Test-CloudGateway.ps1`

Expected: PASS.

### Task 4: Publish

**Files:**
- No source file changes expected.

- [ ] **Step 1: Verify publication readiness**

Run tests, PowerShell/Bash syntax checks, and sensitive-content scan.

- [ ] **Step 2: Initialize git if needed**

If this directory is not a git repository, run `git init`, set branch to `main`,
add files, and commit.

- [ ] **Step 3: Create or connect GitHub repository**

Use `gh` when available. If `gh` is not on PATH, search common install paths and
use the executable directly. If it still cannot be found, report the blocker and
the exact commands for the user to run.

## Self-Review

- This plan does not change deployment behavior.
- Tests come before the README and memory file changes.
- GitHub publication is attempted only after verification passes.
