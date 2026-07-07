# Codex Doctor

Self-diagnostic and cleanup skill for Codex CLI environments.

The default mode is read-only diagnosis. Cleanup requires explicit flags, prints an exact plan, and asks for confirmation unless `--yes` is passed.

## Examples

Diagnose only:

```bash
./scripts/codex-doctor.sh
```

Prune Codex session rollout files older than 30 days:

```bash
./scripts/codex-doctor.sh --prune-codex-sessions-days 30
```

Clear the Codex cache:

```bash
./scripts/codex-doctor.sh --clear-codex-cache
```

Clean Xcode DerivedData:

```bash
./scripts/codex-doctor.sh --clear-xcode-derived-data
```

Skip the confirmation prompt only after reviewing the action:

```bash
./scripts/codex-doctor.sh --prune-codex-sessions-days 30 --yes
```

## What It Inspects

- `~/.codex`, including sessions, largest `rollout-*.jsonl` files, and `logs_2.sqlite*`.
- `~/Library/Caches/com.openai.codex`.
- `~/Library/Developer/Xcode/DerivedData`.
- `~/Library/Developer/CoreSimulator`.
- pip, npm, pnpm, yarn, and Homebrew caches.

## Safety

The cleanup script never targets source code, project folders, `Documents`, `Desktop`, or `Downloads`. Destructive actions are constrained to explicit allowlisted cache and Codex session locations.
