#!/usr/bin/env bash
# Diagnose Codex CLI storage and selected developer caches.
# Default behavior is read-only. Cleanup requires explicit flags and a
# confirmation prompt unless --yes is supplied.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=doctor-common.sh
. "$SCRIPT_DIR/doctor-common.sh"

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_SESSIONS="$CODEX_HOME/sessions"
CODEX_CACHE="$HOME/Library/Caches/com.openai.codex"
XCODE_DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
CORE_SIMULATOR="$HOME/Library/Developer/CoreSimulator"
CODE_SIGN_CLONE_ROOT="$(doctor_detect_codex_code_sign_clone_root || true)"

ASSUME_YES=0
PRUNE_CODEX_SESSIONS_DAYS=""
PRUNE_CODE_SIGN_CLONES_DAYS=""
CLEAR_CODEX_CACHE=0
CLEAR_XCODE_DERIVED_DATA=0
ERASE_SIMULATORS=0
CLEAR_PIP_CACHE=0
CLEAR_NPM_CACHE=0
CLEAR_PNPM_CACHE=0
CLEAR_YARN_CACHE=0
CLEAR_HOMEBREW_CACHE=0

usage() {
  cat <<'USAGE'
Usage: codex-doctor.sh [cleanup flags] [--yes]

Diagnosis is read-only by default.

Cleanup flags:
  --prune-codex-sessions-days N   Remove ~/.codex/sessions rollout-*.jsonl files older than N days.
  --prune-code-sign-clones-days N Remove verified, inactive Codex macOS code-sign clones older than N days.
  --clear-codex-cache             Empty ~/Library/Caches/com.openai.codex.
  --clear-xcode-derived-data      Empty ~/Library/Developer/Xcode/DerivedData.
  --erase-simulators              Run xcrun simctl erase all after shutting down simulators.
  --clear-pip-cache               Purge pip cache using pip, or empty known pip cache directories.
  --clear-npm-cache               Run npm cache clean --force, or empty known npm cache directories.
  --clear-pnpm-cache              Run pnpm store prune, or empty known pnpm store directories.
  --clear-yarn-cache              Run yarn cache clean, or empty known yarn cache directories.
  --clear-homebrew-cache          Run brew cleanup --prune=all --cache when brew is available.
  --yes                           Execute cleanup without interactive confirmation.
  --help                          Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prune-codex-sessions-days)
      shift
      if [ "$#" -eq 0 ] || ! printf '%s' "$1" | grep -Eq '^[0-9]+$'; then
        printf 'Expected a non-negative integer after --prune-codex-sessions-days.\n' >&2
        exit 2
      fi
      PRUNE_CODEX_SESSIONS_DAYS="$1"
      ;;
    --prune-code-sign-clones-days)
      shift
      if [ "$#" -eq 0 ] || ! printf '%s' "$1" | grep -Eq '^[0-9]+$'; then
        printf 'Expected a non-negative integer after --prune-code-sign-clones-days.\n' >&2
        exit 2
      fi
      PRUNE_CODE_SIGN_CLONES_DAYS="$1"
      ;;
    --clear-codex-cache)
      CLEAR_CODEX_CACHE=1
      ;;
    --clear-xcode-derived-data)
      CLEAR_XCODE_DERIVED_DATA=1
      ;;
    --erase-simulators)
      ERASE_SIMULATORS=1
      ;;
    --clear-pip-cache)
      CLEAR_PIP_CACHE=1
      ;;
    --clear-npm-cache)
      CLEAR_NPM_CACHE=1
      ;;
    --clear-pnpm-cache)
      CLEAR_PNPM_CACHE=1
      ;;
    --clear-yarn-cache)
      CLEAR_YARN_CACHE=1
      ;;
    --clear-homebrew-cache)
      CLEAR_HOMEBREW_CACHE=1
      ;;
    --yes)
      ASSUME_YES=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

PIP_CACHE=""
if doctor_command_exists python3; then
  PIP_CACHE="$(python3 -m pip cache dir 2>/dev/null || true)"
fi
if [ -z "$PIP_CACHE" ] && doctor_command_exists pip3; then
  PIP_CACHE="$(pip3 cache dir 2>/dev/null || true)"
fi
if [ -z "$PIP_CACHE" ]; then
  PIP_CACHE="$HOME/Library/Caches/pip"
fi

NPM_CACHE=""
if doctor_command_exists npm; then
  NPM_CACHE="$(npm config get cache 2>/dev/null || true)"
fi
if [ -z "$NPM_CACHE" ] || [ "$NPM_CACHE" = "undefined" ]; then
  NPM_CACHE="$HOME/.npm"
fi

PNPM_CACHE=""
if doctor_command_exists pnpm; then
  PNPM_CACHE="$(pnpm store path 2>/dev/null || true)"
fi
if [ -z "$PNPM_CACHE" ]; then
  PNPM_CACHE="$HOME/Library/pnpm/store"
fi

YARN_CACHE=""
if doctor_command_exists yarn; then
  YARN_CACHE="$(yarn cache dir 2>/dev/null || true)"
fi
if [ -z "$YARN_CACHE" ]; then
  YARN_CACHE="$HOME/Library/Caches/Yarn"
fi

HOMEBREW_CACHE=""
if doctor_command_exists brew; then
  HOMEBREW_CACHE="$(brew --cache 2>/dev/null || true)"
fi
if [ -z "$HOMEBREW_CACHE" ]; then
  HOMEBREW_CACHE="$HOME/Library/Caches/Homebrew"
fi

CODE_SIGN_CLONE_PATHS=()
CODE_SIGN_CLONE_VERSIONS=()
CODE_SIGN_CLONE_BUILDS=()
CODE_SIGN_CLONE_AGES=()
CODE_SIGN_CLONE_STATUSES=()
CODE_SIGN_CLONE_SIZES=()
CODE_SIGN_CLONE_TOTAL_KB=0
CODE_SIGN_CLONE_INVALID_COUNT=0

if [ -n "$CODE_SIGN_CLONE_ROOT" ] && [ -d "$CODE_SIGN_CLONE_ROOT" ]; then
  shopt -s nullglob
  raw_code_sign_clones=("$CODE_SIGN_CLONE_ROOT"/code_sign_clone.*)
  shopt -u nullglob
  for clone_path in "${raw_code_sign_clones[@]}"; do
    if ! clone_bundle="$(doctor_codex_clone_bundle "$clone_path")"; then
      CODE_SIGN_CLONE_INVALID_COUNT=$((CODE_SIGN_CLONE_INVALID_COUNT + 1))
      continue
    fi
    clone_plist="$clone_bundle/Contents/Info.plist"
    clone_version="$(doctor_plist_value "$clone_plist" CFBundleShortVersionString || printf 'unknown')"
    clone_build="$(doctor_plist_value "$clone_plist" CFBundleVersion || printf 'unknown')"
    clone_age="$(doctor_path_age_days "$clone_path" || printf '0')"
    clone_status="$(doctor_codex_clone_status "$clone_path")"
    clone_kb="$(doctor_path_kb "$clone_path")"

    CODE_SIGN_CLONE_PATHS+=("$clone_path")
    CODE_SIGN_CLONE_VERSIONS+=("$clone_version")
    CODE_SIGN_CLONE_BUILDS+=("$clone_build")
    CODE_SIGN_CLONE_AGES+=("$clone_age")
    CODE_SIGN_CLONE_STATUSES+=("$clone_status")
    CODE_SIGN_CLONE_SIZES+=("$clone_kb")
    CODE_SIGN_CLONE_TOTAL_KB=$((CODE_SIGN_CLONE_TOTAL_KB + clone_kb))
  done
fi

printf 'Codex Doctor Report\n'
printf 'Generated: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"

printf 'Codex CLI\n'
doctor_print_size_line '~/.codex total' "$CODEX_HOME"
doctor_print_size_line '~/.codex/sessions' "$CODEX_SESSIONS"
doctor_print_size_line 'logs_2.sqlite' "$CODEX_HOME/logs_2.sqlite"
doctor_print_size_line 'logs_2.sqlite-wal' "$CODEX_HOME/logs_2.sqlite-wal"
doctor_print_size_line 'logs_2.sqlite-shm' "$CODEX_HOME/logs_2.sqlite-shm"
doctor_print_size_line 'Codex cache' "$CODEX_CACHE"

printf '\nLargest rollout-*.jsonl files\n'
if [ -d "$CODEX_SESSIONS" ]; then
  find "$CODEX_SESSIONS" -type f -name 'rollout-*.jsonl' -exec du -sk {} + 2>/dev/null \
    | sort -nr \
    | head -20 \
    | awk '{ kb=$1; $1=""; sub(/^ /,""); printf "  %12s  %s\n", kb " KB", $0 }' \
    || true
else
  printf '  Not found: %s\n' "$CODEX_SESSIONS"
fi

printf '\nDeveloper Caches\n'
doctor_print_size_line 'Xcode DerivedData' "$XCODE_DERIVED_DATA"
doctor_print_size_line 'CoreSimulator' "$CORE_SIMULATOR"
doctor_print_size_line 'pip cache' "$PIP_CACHE"
doctor_print_size_line 'npm cache' "$NPM_CACHE"
doctor_print_size_line 'pnpm store/cache' "$PNPM_CACHE"
doctor_print_size_line 'yarn cache' "$YARN_CACHE"
doctor_print_size_line 'Homebrew cache' "$HOMEBREW_CACHE"

printf '\nCodex macOS Code-Sign Clones\n'
if [ -z "$CODE_SIGN_CLONE_ROOT" ]; then
  printf '  Not available on this platform.\n'
elif [ "${#CODE_SIGN_CLONE_PATHS[@]}" -eq 0 ]; then
  printf '  No verified Codex code-sign clones found at: %s\n' "$CODE_SIGN_CLONE_ROOT"
else
  printf '  Chromium creates these APFS copy-on-write app clones to keep a running\n'
  printf '  Codex instance code-signature-valid while an update replaces the app.\n'
  printf '  Root: %s\n' "$CODE_SIGN_CLONE_ROOT"
  printf '  Verified total (logical/accounted): %s\n' "$(doctor_human_kb "$CODE_SIGN_CLONE_TOTAL_KB")"
  printf '  %-24s %-18s %-8s %-10s %12s\n' 'Clone' 'Version (build)' 'Age' 'Status' 'Size'
  for ((i = 0; i < ${#CODE_SIGN_CLONE_PATHS[@]}; i++)); do
    printf '  %-24s %-18s %5sd   %-10s %12s\n' \
      "${CODE_SIGN_CLONE_PATHS[$i]##*/}" \
      "${CODE_SIGN_CLONE_VERSIONS[$i]} (${CODE_SIGN_CLONE_BUILDS[$i]})" \
      "${CODE_SIGN_CLONE_AGES[$i]}" \
      "${CODE_SIGN_CLONE_STATUSES[$i]}" \
      "$(doctor_human_kb "${CODE_SIGN_CLONE_SIZES[$i]}")"
  done
  printf '  Note: APFS clone block sharing means actual free-space gain may be lower.\n'
fi
if [ "$CODE_SIGN_CLONE_INVALID_COUNT" -gt 0 ]; then
  printf '  Ignored %s unverified artifact(s); they are never cleanup candidates.\n' "$CODE_SIGN_CLONE_INVALID_COUNT"
fi

cleanup_requested=0
selected_reclaimable_kb=0
recommended_reclaimable_kb=0
plan_items=()
risky_plan_items=()
safe_recommendations=()
risky_recommendations=()
prune_files=()
prune_code_sign_clones=()

recommended_prune_files=()
if [ -d "$CODEX_SESSIONS" ]; then
  while IFS= read -r file; do
    recommended_prune_files+=("$file")
  done < <(find "$CODEX_SESSIONS" -type f -name 'rollout-*.jsonl' -mtime +30 -print 2>/dev/null | sort)
fi
if [ "${#recommended_prune_files[@]}" -gt 0 ]; then
  kb="$(doctor_paths_kb "${recommended_prune_files[@]}")"
  recommended_reclaimable_kb=$((recommended_reclaimable_kb + kb))
  safe_recommendations+=("Prune ${#recommended_prune_files[@]} Codex rollout files older than 30 days ($(doctor_human_kb "$kb")): ./scripts/codex-doctor.sh --prune-codex-sessions-days 30")
fi

recommended_code_sign_clones=()
for ((i = 0; i < ${#CODE_SIGN_CLONE_PATHS[@]}; i++)); do
  if [ "${CODE_SIGN_CLONE_STATUSES[$i]}" = "inactive" ] && [ "${CODE_SIGN_CLONE_AGES[$i]}" -gt 7 ]; then
    recommended_code_sign_clones+=("${CODE_SIGN_CLONE_PATHS[$i]}")
  fi
done
if [ "${#recommended_code_sign_clones[@]}" -gt 0 ]; then
  kb="$(doctor_paths_kb "${recommended_code_sign_clones[@]}")"
  recommended_reclaimable_kb=$((recommended_reclaimable_kb + kb))
  safe_recommendations+=("Prune ${#recommended_code_sign_clones[@]} verified inactive Codex code-sign clones older than 7 days ($(doctor_human_kb "$kb") logical/accounted): ./scripts/codex-doctor.sh --prune-code-sign-clones-days 7")
fi

for recommended_path in "$CODEX_CACHE" "$XCODE_DERIVED_DATA" "$PIP_CACHE" "$NPM_CACHE" "$PNPM_CACHE" "$YARN_CACHE" "$HOMEBREW_CACHE"; do
  kb="$(doctor_path_kb "$recommended_path")"
  recommended_reclaimable_kb=$((recommended_reclaimable_kb + kb))
done

safe_recommendations+=("Clear Codex cache ($(doctor_human_kb "$(doctor_path_kb "$CODEX_CACHE")")): ./scripts/codex-doctor.sh --clear-codex-cache")
safe_recommendations+=("Clear Xcode DerivedData ($(doctor_human_kb "$(doctor_path_kb "$XCODE_DERIVED_DATA")")): ./scripts/codex-doctor.sh --clear-xcode-derived-data")
safe_recommendations+=("Clear package-manager caches ($(doctor_human_kb "$(doctor_paths_kb "$PIP_CACHE" "$NPM_CACHE" "$PNPM_CACHE" "$YARN_CACHE")")): use --clear-pip-cache, --clear-npm-cache, --clear-pnpm-cache, and --clear-yarn-cache as needed")
safe_recommendations+=("Clear Homebrew cache ($(doctor_human_kb "$(doctor_path_kb "$HOMEBREW_CACHE")")): ./scripts/codex-doctor.sh --clear-homebrew-cache")
risky_recommendations+=("Erase simulator content ($(doctor_human_kb "$(doctor_path_kb "$CORE_SIMULATOR")")): ./scripts/codex-doctor.sh --erase-simulators")

if [ -n "$PRUNE_CODEX_SESSIONS_DAYS" ]; then
  cleanup_requested=1
  if [ -d "$CODEX_SESSIONS" ]; then
    while IFS= read -r file; do
      prune_files+=("$file")
    done < <(find "$CODEX_SESSIONS" -type f -name 'rollout-*.jsonl' -mtime +"$PRUNE_CODEX_SESSIONS_DAYS" -print 2>/dev/null | sort)
  fi
  if [ "${#prune_files[@]}" -gt 0 ]; then
    prune_kb="$(doctor_paths_kb "${prune_files[@]}")"
    selected_reclaimable_kb=$((selected_reclaimable_kb + prune_kb))
    plan_items+=("Prune ${#prune_files[@]} Codex rollout files older than ${PRUNE_CODEX_SESSIONS_DAYS} days ($(doctor_human_kb "$prune_kb")).")
  else
    plan_items+=("No Codex rollout files older than ${PRUNE_CODEX_SESSIONS_DAYS} days were found.")
  fi
fi

if [ -n "$PRUNE_CODE_SIGN_CLONES_DAYS" ]; then
  cleanup_requested=1
  skipped_in_use=0
  skipped_recent=0
  skipped_unknown=0
  for ((i = 0; i < ${#CODE_SIGN_CLONE_PATHS[@]}; i++)); do
    if [ "${CODE_SIGN_CLONE_STATUSES[$i]}" = "in use" ]; then
      skipped_in_use=$((skipped_in_use + 1))
    elif [ "${CODE_SIGN_CLONE_STATUSES[$i]}" != "inactive" ]; then
      skipped_unknown=$((skipped_unknown + 1))
    elif [ "${CODE_SIGN_CLONE_AGES[$i]}" -le "$PRUNE_CODE_SIGN_CLONES_DAYS" ]; then
      skipped_recent=$((skipped_recent + 1))
    else
      prune_code_sign_clones+=("${CODE_SIGN_CLONE_PATHS[$i]}")
    fi
  done

  if [ "${#prune_code_sign_clones[@]}" -gt 0 ]; then
    clone_prune_kb="$(doctor_paths_kb "${prune_code_sign_clones[@]}")"
    selected_reclaimable_kb=$((selected_reclaimable_kb + clone_prune_kb))
    plan_items+=("Remove ${#prune_code_sign_clones[@]} verified inactive Codex code-sign clones older than ${PRUNE_CODE_SIGN_CLONES_DAYS} days ($(doctor_human_kb "$clone_prune_kb") logical/accounted; physical APFS gain may be lower).")
  else
    plan_items+=("No verified inactive Codex code-sign clones older than ${PRUNE_CODE_SIGN_CLONES_DAYS} days were found.")
  fi
  if [ "$skipped_in_use" -gt 0 ] || [ "$skipped_recent" -gt 0 ] || [ "$skipped_unknown" -gt 0 ]; then
    plan_items+=("Skip code-sign clones: $skipped_in_use in use, $skipped_recent too recent, $skipped_unknown with unknown status.")
  fi
fi

if [ "$CLEAR_CODEX_CACHE" = "1" ]; then
  cleanup_requested=1
  kb="$(doctor_path_kb "$CODEX_CACHE")"
  selected_reclaimable_kb=$((selected_reclaimable_kb + kb))
  plan_items+=("Empty Codex cache at $CODEX_CACHE ($(doctor_human_kb "$kb")).")
fi

if [ "$CLEAR_XCODE_DERIVED_DATA" = "1" ]; then
  cleanup_requested=1
  kb="$(doctor_path_kb "$XCODE_DERIVED_DATA")"
  selected_reclaimable_kb=$((selected_reclaimable_kb + kb))
  plan_items+=("Empty Xcode DerivedData at $XCODE_DERIVED_DATA ($(doctor_human_kb "$kb")).")
fi

if [ "$ERASE_SIMULATORS" = "1" ]; then
  cleanup_requested=1
  kb="$(doctor_path_kb "$CORE_SIMULATOR")"
  selected_reclaimable_kb=$((selected_reclaimable_kb + kb))
  risky_plan_items+=("Erase all simulator device content with xcrun simctl erase all; current CoreSimulator size is $(doctor_human_kb "$kb").")
fi

if [ "$CLEAR_PIP_CACHE" = "1" ]; then
  cleanup_requested=1
  kb="$(doctor_path_kb "$PIP_CACHE")"
  selected_reclaimable_kb=$((selected_reclaimable_kb + kb))
  plan_items+=("Clear pip cache at $PIP_CACHE ($(doctor_human_kb "$kb")).")
fi

if [ "$CLEAR_NPM_CACHE" = "1" ]; then
  cleanup_requested=1
  kb="$(doctor_path_kb "$NPM_CACHE")"
  selected_reclaimable_kb=$((selected_reclaimable_kb + kb))
  plan_items+=("Clear npm cache at $NPM_CACHE ($(doctor_human_kb "$kb")).")
fi

if [ "$CLEAR_PNPM_CACHE" = "1" ]; then
  cleanup_requested=1
  kb="$(doctor_path_kb "$PNPM_CACHE")"
  selected_reclaimable_kb=$((selected_reclaimable_kb + kb))
  plan_items+=("Prune pnpm store/cache at $PNPM_CACHE ($(doctor_human_kb "$kb")).")
fi

if [ "$CLEAR_YARN_CACHE" = "1" ]; then
  cleanup_requested=1
  kb="$(doctor_path_kb "$YARN_CACHE")"
  selected_reclaimable_kb=$((selected_reclaimable_kb + kb))
  plan_items+=("Clear yarn cache at $YARN_CACHE ($(doctor_human_kb "$kb")).")
fi

if [ "$CLEAR_HOMEBREW_CACHE" = "1" ]; then
  cleanup_requested=1
  kb="$(doctor_path_kb "$HOMEBREW_CACHE")"
  selected_reclaimable_kb=$((selected_reclaimable_kb + kb))
  plan_items+=("Clear Homebrew cache at $HOMEBREW_CACHE ($(doctor_human_kb "$kb")).")
fi

printf '\nCleanup Report\n'
printf '  Total reclaimable estimate for recommended safe items: %s\n' "$(doctor_human_kb "$recommended_reclaimable_kb")"
printf '  Total selected reclaimable estimate: %s\n' "$(doctor_human_kb "$selected_reclaimable_kb")"
printf '  Safe cleanup items:\n'
if [ "${#safe_recommendations[@]}" -eq 0 ]; then
  printf '    None found.\n'
else
  for item in "${safe_recommendations[@]}"; do
    printf '    - %s\n' "$item"
  done
fi
printf '  Risky cleanup items:\n'
if [ "${#risky_recommendations[@]}" -eq 0 ]; then
  printf '    None found.\n'
else
  for item in "${risky_recommendations[@]}"; do
    printf '    - %s\n' "$item"
  done
fi

if [ "$cleanup_requested" = "1" ]; then
  printf '  Selected safe cleanup items:\n'
  if [ "${#plan_items[@]}" -eq 0 ]; then
    printf '    None selected.\n'
  else
    for item in "${plan_items[@]}"; do
      printf '    - %s\n' "$item"
    done
  fi
  printf '  Selected risky cleanup items:\n'
  if [ "${#risky_plan_items[@]}" -eq 0 ]; then
    printf '    None selected.\n'
  else
    for item in "${risky_plan_items[@]}"; do
      printf '    - %s\n' "$item"
    done
  fi
fi

printf '\nRecommended next commands\n'
printf '  ./scripts/codex-doctor.sh --prune-codex-sessions-days 30\n'
printf '  ./scripts/codex-doctor.sh --prune-code-sign-clones-days 7\n'
printf '  ./scripts/codex-doctor.sh --clear-codex-cache\n'
printf '  ./scripts/codex-doctor.sh --clear-xcode-derived-data\n'
printf '  ./scripts/codex-doctor.sh --erase-simulators\n'

if [ "$cleanup_requested" = "0" ]; then
  exit 0
fi

printf '\nExact cleanup plan\n'
if [ "${#prune_files[@]}" -gt 0 ]; then
  printf '  Files to remove:\n'
  for file in "${prune_files[@]}"; do
    printf '    %s\n' "$file"
  done
fi
if [ "${#prune_code_sign_clones[@]}" -gt 0 ]; then
  printf '  Verified inactive code-sign clone directories to remove:\n'
  for clone_path in "${prune_code_sign_clones[@]}"; do
    printf '    %s\n' "$clone_path"
  done
fi
for item in "${plan_items[@]}"; do
  printf '  - %s\n' "$item"
done
if [ "${#risky_plan_items[@]}" -gt 0 ]; then
  for item in "${risky_plan_items[@]}"; do
    printf '  - %s\n' "$item"
  done
fi

doctor_confirm_or_exit "$ASSUME_YES"

if [ "${#prune_files[@]}" -gt 0 ]; then
  for file in "${prune_files[@]}"; do
    doctor_remove_file "$file"
  done
fi

if [ "${#prune_code_sign_clones[@]}" -gt 0 ]; then
  for clone_path in "${prune_code_sign_clones[@]}"; do
    if ! doctor_is_valid_codex_code_sign_clone "$clone_path"; then
      printf 'Skipping clone that failed revalidation: %s\n' "$clone_path" >&2
      continue
    fi
    clone_age="$(doctor_path_age_days "$clone_path" || printf '0')"
    if [ "$clone_age" -le "$PRUNE_CODE_SIGN_CLONES_DAYS" ]; then
      printf 'Skipping clone that is no longer old enough: %s\n' "$clone_path" >&2
      continue
    fi
    if ! doctor_command_exists lsof; then
      printf 'Skipping clone because lsof is unavailable: %s\n' "$clone_path" >&2
      continue
    fi
    if doctor_codex_clone_in_use "$clone_path"; then
      printf 'Skipping clone that became active: %s\n' "$clone_path" >&2
      continue
    else
      clone_use_status=$?
      if [ "$clone_use_status" -ne 1 ]; then
        printf 'Skipping clone whose process status cannot be verified: %s\n' "$clone_path" >&2
        continue
      fi
    fi
    doctor_remove_directory "$clone_path"
  done
fi

if [ "$CLEAR_CODEX_CACHE" = "1" ]; then
  doctor_empty_directory "$CODEX_CACHE"
fi

if [ "$CLEAR_XCODE_DERIVED_DATA" = "1" ]; then
  doctor_empty_directory "$XCODE_DERIVED_DATA"
fi

if [ "$ERASE_SIMULATORS" = "1" ]; then
  if doctor_command_exists xcrun; then
    xcrun simctl shutdown all >/dev/null 2>&1 || true
    xcrun simctl erase all
  else
    printf 'xcrun not found; skipping simulator erase.\n' >&2
  fi
fi

if [ "$CLEAR_PIP_CACHE" = "1" ]; then
  if doctor_command_exists python3; then
    python3 -m pip cache purge || doctor_empty_directory "$PIP_CACHE"
  else
    doctor_empty_directory "$PIP_CACHE"
  fi
fi

if [ "$CLEAR_NPM_CACHE" = "1" ]; then
  if doctor_command_exists npm; then
    npm cache clean --force
  else
    doctor_empty_directory "$NPM_CACHE"
  fi
fi

if [ "$CLEAR_PNPM_CACHE" = "1" ]; then
  if doctor_command_exists pnpm; then
    pnpm store prune
  else
    doctor_empty_directory "$PNPM_CACHE"
  fi
fi

if [ "$CLEAR_YARN_CACHE" = "1" ]; then
  if doctor_command_exists yarn; then
    yarn cache clean
  else
    doctor_empty_directory "$YARN_CACHE"
  fi
fi

if [ "$CLEAR_HOMEBREW_CACHE" = "1" ]; then
  if doctor_command_exists brew; then
    brew cleanup --prune=all --cache
  else
    doctor_empty_directory "$HOMEBREW_CACHE"
  fi
fi

printf '\nCleanup complete.\n'
