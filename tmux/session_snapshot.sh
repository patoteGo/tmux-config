#!/usr/bin/env bash

set -euo pipefail

SNAPSHOT_DIR="${TMUX_SESSION_SNAPSHOT_DIR:-${HOME}/.tmux/snapshots}"
LATEST_LINK="${SNAPSHOT_DIR}/latest.tsv"
KEEP_COUNT="${TMUX_SESSION_SNAPSHOT_KEEP_COUNT:-20}"

tmux_cmd() {
  if [ -n "${TMUX_SOCKET_PATH:-}" ]; then
    tmux -S "${TMUX_SOCKET_PATH}" "$@"
  elif [ -n "${TMUX_SOCKET:-}" ]; then
    tmux -L "${TMUX_SOCKET}" "$@"
  else
    tmux "$@"
  fi
}

ensure_snapshot_dir() {
  mkdir -p "${SNAPSHOT_DIR}"
}

tmux_has_sessions() {
  tmux_cmd list-sessions >/dev/null 2>&1
}

prune_old_snapshots() {
  local count=0
  local file

  for file in $(ls -1t "${SNAPSHOT_DIR}"/tmux_sessions_*.tsv 2>/dev/null); do
    count=$((count + 1))
    if [ "${count}" -gt "${KEEP_COUNT}" ]; then
      rm -f "${file}"
    fi
  done
}

save_snapshot() {
  local reason="${1:-manual}"
  local timestamp
  local tmp_file
  local final_file

  if ! tmux_has_sessions; then
    exit 0
  fi

  ensure_snapshot_dir

  timestamp="$(date +%Y%m%dT%H%M%S)"
  tmp_file="${SNAPSHOT_DIR}/.latest.${timestamp}.$$"
  final_file="${SNAPSHOT_DIR}/tmux_sessions_${timestamp}.tsv"

  {
    printf 'meta\tversion\t1\n'
    printf 'meta\treason\t%s\n' "${reason}"
    printf 'meta\ttimestamp\t%s\n' "${timestamp}"
    tmux_cmd list-sessions -F $'session\t#{session_name}'
    tmux_cmd list-windows -a -F $'window\t#{session_name}\t#{window_index}\t#{window_name}\t#{window_layout}\t#{window_active}\t#{window_panes}'
    tmux_cmd list-panes -a -F $'pane\t#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_active}\t#{pane_current_path}\t#{pane_current_command}\t#{pane_start_command}'
  } > "${tmp_file}"

  mv "${tmp_file}" "${final_file}"
  ln -sfn "$(basename "${final_file}")" "${LATEST_LINK}"

  prune_old_snapshots
}

save_snapshot "${1:-manual}"
