# Codex Doctor

Codex Doctor is a self-diagnostic Skill for Codex CLI environments.

Its purpose is not generic disk cleanup. Its purpose is to help Codex inspect,
explain, and maintain the runtime artifacts created by Codex itself.

## Problem

Long-running agent workflows leave a trail.

Codex sessions, rollout logs, SQLite databases, caches, and temporary runtime
artifacts are useful while work is happening. They make sessions recoverable,
preserve context, speed up repeated operations, and help the CLI function.

Over time, those artifacts accumulate silently. A developer may eventually find
gigabytes of data under `~/.codex` without a clear answer to basic questions:

- What created this?
- Is it still useful?
- Is it safe to remove?
- How much space would cleanup actually recover?

## Motivation

AI agents should be responsible for maintaining their own runtime.

Codex Doctor was created from that idea. If Codex can generate sessions, logs,
rollout files, caches, and local state, Codex should also know how to inspect
those artifacts and explain them clearly.

The goal is understanding first, cleanup second.

## Philosophy

Codex Doctor treats runtime maintenance as part of the agent's job:

- Diagnose before deleting.
- Explain what each artifact is and why it exists.
- Separate safe cleanup from risky cleanup.
- Require explicit cleanup flags for destructive actions.
- Never target source code, project folders, `Documents`, `Desktop`, or
  `Downloads`.

The default mode is read-only. Cleanup only happens when requested.

## Installation

Install manually from GitHub into your Codex skills directory:

```bash
mkdir -p ~/.codex/skills
git clone https://github.com/YizeSun/codex-doctor.git ~/.codex/skills/codex-doctor
```

Verify the Skill files are installed:

```bash
ls ~/.codex/skills/codex-doctor
```

You should see:

```text
SKILL.md
README.md
agents/
scripts/
```

To update later:

```bash
cd ~/.codex/skills/codex-doctor
git pull
```

## Usage

Run a read-only diagnosis:

```bash
~/.codex/skills/codex-doctor/scripts/codex-doctor.sh
```

Common follow-up commands:

```bash
# Prune old Codex rollout session files
~/.codex/skills/codex-doctor/scripts/codex-doctor.sh --prune-codex-sessions-days 30

# Clear the Codex cache
~/.codex/skills/codex-doctor/scripts/codex-doctor.sh --clear-codex-cache

# Clean Xcode DerivedData when local iOS/macOS builds are part of the workflow
~/.codex/skills/codex-doctor/scripts/codex-doctor.sh --clear-xcode-derived-data
```

Cleanup commands print an exact plan and require confirmation unless `--yes` is
passed.

## Real Example

In one real Codex environment, the first read-only inspection found:

```text
~/.codex/sessions          8.44 GB
~/.codex/logs_2.sqlite   352.06 MB
Codex cache                1.79 GB
```

The useful part was not that these files could be deleted. The useful part was
that Codex could explain what it had generated:

- `~/.codex/sessions` contains session and rollout history from prior Codex
  runs.
- `rollout-*.jsonl` files can become very large during long workflows.
- `logs_2.sqlite` and related SQLite files hold local Codex logging state.
- `~/Library/Caches/com.openai.codex` stores cache data used by the Codex CLI.

The workflow becomes:

1. Ask Codex to inspect its runtime.
2. Review the largest Codex-generated artifacts.
3. Understand why each artifact exists.
4. See a reclaimable-space estimate.
5. Choose whether to run a targeted cleanup command.

For that environment, Codex Doctor could recommend safe cleanup such as pruning
old rollout files or clearing the Codex cache, while marking simulator erasure
as risky because it removes simulator device state.

This is the core value of the project: Codex becomes able to account for its own
local footprint.

## Safety

Codex Doctor is conservative by default.

- Diagnosis is read-only.
- Cleanup requires explicit flags.
- Destructive actions print an exact cleanup plan first.
- Confirmation is required unless `--yes` is passed.
- Cleanup paths are allowlisted.
- Source code, project folders, `Documents`, `Desktop`, and `Downloads` are not
  cleanup targets.

The script also reports common developer caches because Codex workflows often
drive local builds and package managers. Those checks are supporting context,
not the main scope of the project.

## Roadmap

- Better explanations for each Codex artifact type.
- Machine-readable JSON reports for automation.
- Threshold-based recommendations for unusually large session or log files.
- Safer SQLite maintenance options where supported.
- More Codex-specific runtime checks as the CLI evolves.
