#!/usr/bin/env bash

set -euo pipefail

RESURRECT_DIR="${HOME}/.tmux/resurrect"
LAST_LINK="${RESURRECT_DIR}/last"
RESTORE_SCRIPT="${HOME}/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

kill_stuck_spinner() {
  pkill -f 'tmux_spinner.sh Restoring...' >/dev/null 2>&1 || true
  pkill -f '/tmux-resurrect/scripts/tmux_spinner.sh' >/dev/null 2>&1 || true
}

current_pane_count() {
  if [ -f "${LAST_LINK}" ]; then
    grep -c '^pane' "${LAST_LINK}" || true
  else
    printf '0\n'
  fi
}

find_better_snapshot() {
  local current_count="$1"
  local current_target=""

  if [ -L "${LAST_LINK}" ]; then
    current_target="$(readlink "${LAST_LINK}")"
  fi

  for file in $(ls -1t "${RESURRECT_DIR}"/tmux_resurrect_*.txt 2>/dev/null); do
    local base
    local pane_count

    base="$(basename "${file}")"
    [ "${base}" = "${current_target}" ] && continue

    pane_count="$(grep -c '^pane' "${file}" || true)"
    if [ "${pane_count}" -gt "${current_count}" ]; then
      printf '%s\n' "${base}"
      return 0
    fi
  done

  return 1
}

main() {
  if [ ! -x "${RESTORE_SCRIPT}" ]; then
    tmux display-message "tmux-resurrect restore script not found"
    exit 1
  fi

  kill_stuck_spinner

  local current_count
  current_count="$(current_pane_count)"

  local snapshot=""
  if snapshot="$(find_better_snapshot "${current_count}")"; then
    ln -fs "${snapshot}" "${LAST_LINK}"
    tmux display-message "Rescue restore using ${snapshot}"
  else
    tmux display-message "No fuller tmux snapshot found; retrying current restore"
  fi

  "${RESTORE_SCRIPT}"
}

main "$@"
