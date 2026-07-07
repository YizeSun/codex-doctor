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

Clone this repository directly into your Codex skills directory:

```bash
mkdir -p ~/.codex/skills
git clone https://github.com/YizeSun/codex-doctor.git ~/.codex/skills/codex-doctor
```

This installs the repository as a single Skill at
`~/.codex/skills/codex-doctor`.

After installing, restart Codex CLI or start a new Codex session so the Skill
can be discovered.

### Verify Installation

Confirm the Skill root contains the expected files:

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

You can also run a read-only diagnosis directly:

```bash
~/.codex/skills/codex-doctor/scripts/codex-doctor.sh --help
```

To update later:

```bash
cd ~/.codex/skills/codex-doctor
git pull
```

## Platform Support

Codex Doctor was originally developed and tested on macOS.

The primary focus is maintaining the local Codex runtime under macOS, where
Codex is commonly used alongside developer tooling such as Xcode.

Most Codex runtime checks are platform-independent.

Some supporting diagnostics, for example developer cache inspection, are
currently macOS-specific.

Support for additional operating systems may be added in the future.

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

After several weeks of intensive Codex usage, I noticed that my Mac's
`System Data` had grown unexpectedly.

My first assumption was the usual one: Xcode or iOS Simulator had probably left
behind build artifacts. I spent time checking the obvious places, including
DerivedData and simulator storage.

But a significant amount of space was coming from somewhere else: Codex runtime
artifacts, especially under `~/.codex`.

That changed the question. The problem was not "what can I delete?"

The problem was:

```text
What exactly has Codex generated?
```

So I ran Codex Doctor to investigate the runtime before taking action.

### Diagnosis

```text
~/.codex/sessions        8.44 GB
Largest rollout file     3.52 GB
SQLite logs            352.06 MB
Codex cache              1.79 GB
```

The diagnosis made the storage visible. The important part was the next step:
understanding what those artifacts were.

### Explanation

- `~/.codex/sessions` contained history from long-running agent workflows.
- The largest `rollout-*.jsonl` file was a detailed trace from an unusually
  large session.
- `logs_2.sqlite` was local Codex logging state, not a project database.
- `~/Library/Caches/com.openai.codex` was cache data created by the Codex CLI.

### Recommendation

```text
Estimated reclaimable storage from safe cleanup: 10.2 GB
```

Codex Doctor separated safe cleanup candidates from riskier actions and showed
the exact commands that would perform each cleanup.

### Human Decision

Nothing was deleted automatically.

With the runtime explained, the decision became straightforward: keep recent
session history, prune older rollout files, and clear cache data that could be
regenerated.

### Result

The result was not just reclaimed storage. The useful result was confidence:
Codex could account for its own local footprint, and the user could decide what
to keep based on understanding rather than guesswork.

That debugging session became the motivation for Codex Doctor.

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
