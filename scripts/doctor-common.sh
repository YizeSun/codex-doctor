#!/usr/bin/env bash
# Shared helpers for codex-doctor.sh.
# Keep cleanup helpers conservative: every destructive operation must pass an
# allowlist check and be triggered from an explicit flag in the main script.

set -u

doctor_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

doctor_path_kb() {
  local path="$1"
  if [ -e "$path" ]; then
    du -sk "$path" 2>/dev/null | awk '{print $1}'
  else
    printf '0\n'
  fi
}

doctor_paths_kb() {
  local total=0
  local kb
  local path
  for path in "$@"; do
    kb="$(doctor_path_kb "$path")"
    total=$((total + kb))
  done
  printf '%s\n' "$total"
}

doctor_human_kb() {
  awk -v kb="${1:-0}" 'BEGIN {
    split("KB MB GB TB", unit, " ");
    value = kb + 0;
    idx = 1;
    while (value >= 1024 && idx < 4) {
      value = value / 1024;
      idx++;
    }
    if (idx == 1) {
      printf "%d %s", value, unit[idx];
    } else {
      printf "%.2f %s", value, unit[idx];
    }
  }'
}

doctor_print_size_line() {
  local label="$1"
  local path="$2"
  local kb
  kb="$(doctor_path_kb "$path")"
  printf '  %-36s %12s  %s\n' "$label" "$(doctor_human_kb "$kb")" "$path"
}

doctor_confirm_or_exit() {
  local assume_yes="$1"
  if [ "$assume_yes" = "1" ]; then
    return 0
  fi

  printf '\nType "yes" to execute this cleanup plan: '
  local answer
  read -r answer || answer=""
  if [ "$answer" != "yes" ]; then
    printf 'Cleanup cancelled.\n'
    exit 1
  fi
}

doctor_is_allowed_cleanup_path() {
  local path="$1"
  case "$path" in
    ""|"/"|"$HOME"|"$HOME/"|"$HOME/Desktop"|"$HOME/Desktop/"|"$HOME/Documents"|"$HOME/Documents/"|"$HOME/Downloads"|"$HOME/Downloads/")
      return 1
      ;;
  esac

  case "$path" in
    "$HOME/.codex/sessions"|"$HOME/.codex/sessions/"*|"$HOME/.codex/logs_2.sqlite"|"$HOME/.codex/logs_2.sqlite-"*|"$HOME/Library/Caches/com.openai.codex"|"$HOME/Library/Caches/com.openai.codex/"*|"$HOME/Library/Developer/Xcode/DerivedData"|"$HOME/Library/Developer/Xcode/DerivedData/"*|"$HOME/Library/Developer/CoreSimulator"|"$HOME/Library/Developer/CoreSimulator/"*|"$HOME/Library/Caches/pip"|"$HOME/Library/Caches/pip/"*|"$HOME/.cache/pip"|"$HOME/.cache/pip/"*|"$HOME/Library/Caches/npm"|"$HOME/Library/Caches/npm/"*|"$HOME/.npm"|"$HOME/.npm/"*|"$HOME/Library/pnpm/store"|"$HOME/Library/pnpm/store/"*|"$HOME/.pnpm-store"|"$HOME/.pnpm-store/"*|"$HOME/Library/Caches/Yarn"|"$HOME/Library/Caches/Yarn/"*|"$HOME/.cache/yarn"|"$HOME/.cache/yarn/"*|"$HOME/Library/Caches/Homebrew"|"$HOME/Library/Caches/Homebrew/"*)
      return 0
      ;;
  esac

  return 1
}

doctor_empty_directory() {
  local path="$1"
  if ! doctor_is_allowed_cleanup_path "$path"; then
    printf 'Refusing to clean non-allowlisted path: %s\n' "$path" >&2
    return 1
  fi
  if [ -d "$path" ]; then
    find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
}

doctor_remove_file() {
  local path="$1"
  if ! doctor_is_allowed_cleanup_path "$path"; then
    printf 'Refusing to remove non-allowlisted path: %s\n' "$path" >&2
    return 1
  fi
  if [ -f "$path" ]; then
    rm -f "$path"
  fi
}
