---
name: codex-doctor
description: Diagnose Codex CLI disk usage, bloated ~/.codex sessions/logs, Codex cache growth, stale macOS Codex code-sign clones, and common macOS developer caches. Use when Codex is asked to inspect, explain, report, or safely clean local Codex CLI storage, rollout JSONL files, logs_2.sqlite files, ~/Library/Caches/com.openai.codex, com.openai.codex.code_sign_clone, Xcode DerivedData, CoreSimulator, pip/npm/pnpm/yarn caches, or Homebrew cache.
---

# Codex Doctor

Use this skill to diagnose Codex CLI storage and prepare conservative cleanup commands for local development machines.

## Default Workflow

1. Run the bundled script in read-only mode first:

```bash
./scripts/codex-doctor.sh
```

2. Review the report sections:
- `Codex CLI`: `~/.codex` size, session size, largest `rollout-*.jsonl` files, and `logs_2.sqlite*` sizes.
- `Codex macOS Code-Sign Clones`: verified app clones, versions, age, process-use state, and logical/accounted size.
- `Developer Caches`: Xcode, simulator, package-manager, and Homebrew cache sizes.
- `Cleanup Report`: reclaimable estimate, safe cleanup items, risky cleanup items, and recommended next commands.

3. Only perform cleanup when the user explicitly asks for it or provides cleanup flags. Cleanup must print an exact plan and require confirmation unless `--yes` is passed.

## Cleanup Commands

Use these flags only after diagnosis:

```bash
./scripts/codex-doctor.sh --prune-codex-sessions-days 30
./scripts/codex-doctor.sh --clear-codex-cache
./scripts/codex-doctor.sh --prune-code-sign-clones-days 7
./scripts/codex-doctor.sh --clear-xcode-derived-data
./scripts/codex-doctor.sh --erase-simulators
```

Combine flags when appropriate:

```bash
./scripts/codex-doctor.sh --prune-codex-sessions-days 30 --clear-codex-cache
```

Use `--yes` only when the user has explicitly approved unattended cleanup:

```bash
./scripts/codex-doctor.sh --prune-codex-sessions-days 30 --yes
```

## Safety Rules

- Default to diagnosis only.
- Never delete source code, project folders, `Documents`, `Desktop`, or `Downloads`.
- Delete only from the script's allowlisted Codex, cache, Xcode DerivedData, simulator, package-manager, or Homebrew cache paths.
- Delete code-sign clones only when their directory shape, owner, Bundle ID, age, and inactive process state all pass validation. Recheck immediately before deletion.
- Never count an active, recent, malformed, symlinked, or unverifiable code-sign clone as safe cleanup.
- Treat simulator erasure as risky because it removes simulator app data and device state.
- Prefer pruning old Codex rollout files over removing all sessions.

## Bundled Resources

- `scripts/codex-doctor.sh`: main diagnostic and cleanup CLI.
- `scripts/doctor-common.sh`: shared size, reporting, confirmation, and deletion guards.
