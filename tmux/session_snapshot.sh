#!/usr/bin/env bash

set -euo pipefail

SNAPSHOT_DIR="${TMUX_SESSION_SNAPSHOT_DIR:-${HOME}/.tmux/snapshots}"
LATEST_LINK="${SNAPSHOT_DIR}/latest.tsv"
KEEP_COUNT="${TMUX_SESSION_SNAPSHOT_KEEP_COUNT:-20}"
MIN_INTERVAL="${TMUX_SESSION_SNAPSHOT_MIN_INTERVAL:-2}"
LOCK_DIR="${SNAPSHOT_DIR}/.snapshot.lock"
LAST_RUN_FILE="${SNAPSHOT_DIR}/.last_snapshot_epoch"

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

release_lock() {
  rm -rf "${LOCK_DIR}"
}

lock_is_stale() {
  local pid

  if [ ! -f "${LOCK_DIR}/pid" ]; then
    return 0
  fi

  pid="$(cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
  if [ -z "${pid}" ]; then
    return 0
  fi

  if kill -0 "${pid}" 2>/dev/null; then
    return 1
  fi

  return 0
}

acquire_lock() {
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    printf '%s\n' "$$" > "${LOCK_DIR}/pid"
    trap release_lock EXIT INT TERM
    return 0
  fi

  if lock_is_stale; then
    rm -rf "${LOCK_DIR}"
    mkdir "${LOCK_DIR}"
    printf '%s\n' "$$" > "${LOCK_DIR}/pid"
    trap release_lock EXIT INT TERM
    return 0
  fi

  exit 0
}

should_skip_snapshot() {
  local reason="$1"
  local now
  local last_run

  if [ "${reason}" = "manual" ]; then
    return 1
  fi

  if ! [[ "${MIN_INTERVAL}" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if [ "${MIN_INTERVAL}" -le 0 ] || [ ! -f "${LAST_RUN_FILE}" ]; then
    return 1
  fi

  now="$(date +%s)"
  last_run="$(cat "${LAST_RUN_FILE}" 2>/dev/null || true)"

  if ! [[ "${last_run}" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if [ $((now - last_run)) -lt "${MIN_INTERVAL}" ]; then
    return 0
  fi

  return 1
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
  local epoch
  local tmp_file
  local final_file

  if ! tmux_has_sessions; then
    exit 0
  fi

  ensure_snapshot_dir
  acquire_lock

  if should_skip_snapshot "${reason}"; then
    exit 0
  fi

  timestamp="$(date +%Y%m%dT%H%M%S)"
  epoch="$(date +%s)"
  tmp_file="${SNAPSHOT_DIR}/.latest.${timestamp}.$$.tmp"
  final_file="${SNAPSHOT_DIR}/tmux_sessions_${timestamp}_$$.tsv"

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
  printf '%s\n' "${epoch}" > "${LAST_RUN_FILE}"

  prune_old_snapshots
}

save_snapshot "${1:-manual}"
