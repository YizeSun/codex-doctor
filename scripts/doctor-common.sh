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

doctor_detect_codex_code_sign_clone_root() {
  if [ "${CODEX_DOCTOR_TEST_MODE:-0}" = "1" ] && [ -n "${CODEX_CODE_SIGN_CLONE_ROOT:-}" ]; then
    printf '%s\n' "${CODEX_CODE_SIGN_CLONE_ROOT%/}"
    return 0
  fi

  if [ "$(uname -s 2>/dev/null || true)" != "Darwin" ]; then
    return 1
  fi

  local darwin_temp
  darwin_temp="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
  if [ -z "$darwin_temp" ]; then
    return 1
  fi

  darwin_temp="${darwin_temp%/}"
  printf '%s/X/com.openai.codex.code_sign_clone\n' "${darwin_temp%/*}"
}

doctor_real_directory() {
  local path="$1"
  (cd "$path" 2>/dev/null && pwd -P)
}

doctor_file_owner_uid() {
  local path="$1"
  stat -f '%u' "$path" 2>/dev/null || stat -c '%u' "$path" 2>/dev/null
}

doctor_file_mtime_epoch() {
  local path="$1"
  stat -f '%m' "$path" 2>/dev/null || stat -c '%Y' "$path" 2>/dev/null
}

doctor_path_age_days() {
  local path="$1"
  local modified
  local now
  modified="$(doctor_file_mtime_epoch "$path")" || return 1
  now="${DOCTOR_NOW_EPOCH:-$(date '+%s')}"
  if [ "$modified" -gt "$now" ]; then
    printf '0\n'
  else
    printf '%s\n' "$(( (now - modified) / 86400 ))"
  fi
}

doctor_plist_value() {
  local plist="$1"
  local key="$2"
  if [ -x /usr/libexec/PlistBuddy ]; then
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null
  elif doctor_command_exists plutil; then
    plutil -extract "$key" raw -o - "$plist" 2>/dev/null
  else
    return 1
  fi
}

doctor_codex_clone_bundle() {
  local path="$1"
  local root="${CODE_SIGN_CLONE_ROOT:-}"
  local name
  local parent_real
  local root_real
  local owner_uid
  local plist
  local bundle_id
  local executable
  local bundles=()

  [ -n "$root" ] || return 1
  [ -d "$path" ] || return 1
  [ ! -L "$path" ] || return 1

  name="${path##*/}"
  [[ "$name" =~ ^code_sign_clone\.[A-Za-z0-9._-]{6}$ ]] || return 1

  root_real="$(doctor_real_directory "$root")" || return 1
  parent_real="$(doctor_real_directory "${path%/*}")" || return 1
  [ "$parent_real" = "$root_real" ] || return 1

  owner_uid="$(doctor_file_owner_uid "$path")" || return 1
  [ "$owner_uid" = "$(id -u)" ] || return 1

  shopt -s nullglob
  bundles=("$path"/*.app.bundle)
  shopt -u nullglob
  [ "${#bundles[@]}" -eq 1 ] || return 1
  [ -d "${bundles[0]}" ] || return 1
  [ ! -L "${bundles[0]}" ] || return 1

  plist="${bundles[0]}/Contents/Info.plist"
  [ -f "$plist" ] || return 1
  bundle_id="$(doctor_plist_value "$plist" CFBundleIdentifier)" || return 1
  [ "$bundle_id" = "com.openai.codex" ] || return 1
  executable="$(doctor_plist_value "$plist" CFBundleExecutable)" || return 1
  [ -n "$executable" ] || return 1
  [ -f "${bundles[0]}/Contents/MacOS/$executable" ] || return 1

  printf '%s\n' "${bundles[0]}"
}

doctor_is_valid_codex_code_sign_clone() {
  doctor_codex_clone_bundle "$1" >/dev/null
}

doctor_codex_clone_in_use() {
  local path="$1"
  local bundle
  local executable
  local main_executable
  local opened
  local lsof_status

  doctor_command_exists lsof || return 2
  bundle="$(doctor_codex_clone_bundle "$path")" || return 2
  executable="$(doctor_plist_value "$bundle/Contents/Info.plist" CFBundleExecutable)" || return 2
  main_executable="$bundle/Contents/MacOS/$executable"

  # Querying the main executable by path also catches a process using another
  # hard link to the same inode, which is the core purpose of these clones.
  lsof_status=0
  opened="$(lsof -nP "$main_executable" 2>&1)" || lsof_status=$?
  if printf '%s\n' "$opened" | grep -Eq '^COMMAND[[:space:]]'; then
    return 0
  fi
  if [ -n "$opened" ] || { [ "$lsof_status" -ne 0 ] && [ "$lsof_status" -ne 1 ]; }; then
    return 2
  fi

  lsof_status=0
  opened="$(lsof -nP +D "$path" 2>&1)" || lsof_status=$?
  if printf '%s\n' "$opened" | grep -Eq '^COMMAND[[:space:]]'; then
    return 0
  fi
  if [ -n "$opened" ] || { [ "$lsof_status" -ne 0 ] && [ "$lsof_status" -ne 1 ]; }; then
    return 2
  fi

  return 1
}

doctor_codex_clone_status() {
  local path="$1"
  local in_use_status
  if ! doctor_command_exists lsof; then
    printf 'unknown (lsof unavailable)\n'
    return 0
  fi
  if doctor_codex_clone_in_use "$path"; then
    printf 'in use\n'
  else
    in_use_status=$?
    if [ "$in_use_status" -eq 1 ]; then
      printf 'inactive\n'
    else
      printf 'unknown (check failed)\n'
    fi
  fi
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

  if [ -n "${CODE_SIGN_CLONE_ROOT:-}" ] && doctor_is_valid_codex_code_sign_clone "$path"; then
    return 0
  fi

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

doctor_remove_directory() {
  local path="$1"
  if ! doctor_is_allowed_cleanup_path "$path"; then
    printf 'Refusing to remove non-allowlisted directory: %s\n' "$path" >&2
    return 1
  fi
  if [ -L "$path" ]; then
    printf 'Refusing to follow directory symlink: %s\n' "$path" >&2
    return 1
  fi
  if [ -d "$path" ]; then
    rm -rf -- "$path"
  fi
}
