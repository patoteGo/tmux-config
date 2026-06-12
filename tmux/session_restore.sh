#!/usr/bin/env bash

set -euo pipefail

SNAPSHOT_DIR="${TMUX_SESSION_SNAPSHOT_DIR:-${HOME}/.tmux/snapshots}"
DEFAULT_SNAPSHOT="${SNAPSHOT_DIR}/latest.tsv"

declare -a SESSION_ORDER=()
declare -A SESSION_SEEN=()
declare -A SESSION_WINDOWS=()
declare -A WINDOW_NAME=()
declare -A WINDOW_LAYOUT=()
declare -A WINDOW_ACTIVE=()
declare -A WINDOW_FIRST_PATH=()
declare -A WINDOW_PANE_COUNT=()
declare -A WINDOW_PANES=()
declare -A PANE_PATH=()
declare -A PANE_ACTIVE=()

tmux_cmd() {
  if [ -n "${TMUX_SOCKET_PATH:-}" ]; then
    tmux -S "${TMUX_SOCKET_PATH}" "$@"
  elif [ -n "${TMUX_SOCKET:-}" ]; then
    tmux -L "${TMUX_SOCKET}" "$@"
  else
    tmux "$@"
  fi
}

notify() {
  local message="$1"

  if [ -n "${TMUX:-}" ]; then
    tmux_cmd display-message "${message}"
  else
    printf '%s\n' "${message}"
  fi
}

add_session() {
  local session="$1"

  if [ -z "${SESSION_SEEN[${session}]+x}" ]; then
    SESSION_SEEN["${session}"]=1
    SESSION_ORDER+=("${session}")
    SESSION_WINDOWS["${session}"]=""
  fi
}

add_window() {
  local session="$1"
  local window_index="$2"
  local window_list=" ${SESSION_WINDOWS[${session}]} "
  local key="${session}|${window_index}"

  if [[ "${window_list}" != *" ${window_index} "* ]]; then
    SESSION_WINDOWS["${session}"]+="${window_index} "
  fi

  printf '%s' "${key}"
}

load_snapshot() {
  local snapshot_file="$1"

  if [ ! -f "${snapshot_file}" ]; then
    notify "tmux snapshot not found: ${snapshot_file}"
    exit 1
  fi

  while IFS=$'\t' read -r record_type col2 col3 col4 col5 col6 col7 col8; do
    case "${record_type}" in
      session)
        add_session "${col2}"
        ;;
      window)
        add_session "${col2}"
        WINDOW_NAME["$(add_window "${col2}" "${col3}")"]="${col4}"
        WINDOW_LAYOUT["${col2}|${col3}"]="${col5}"
        WINDOW_ACTIVE["${col2}|${col3}"]="${col6}"
        WINDOW_PANE_COUNT["${col2}|${col3}"]="${col7}"
        ;;
      pane)
        add_session "${col2}"
        add_window "${col2}" "${col3}" >/dev/null
        if [ -z "${WINDOW_FIRST_PATH[${col2}|${col3}]+x}" ] && [ -n "${col6}" ]; then
          WINDOW_FIRST_PATH["${col2}|${col3}"]="${col6}"
        fi
        WINDOW_PANES["${col2}|${col3}"]+="${col4} "
        PANE_PATH["${col2}|${col3}|${col4}"]="${col6}"
        PANE_ACTIVE["${col2}|${col3}|${col4}"]="${col5}"
        ;;
    esac
  done < "${snapshot_file}"
}

session_exists() {
  local session="$1"
  tmux_cmd has-session -t "${session}" 2>/dev/null
}

window_exists() {
  local session="$1"
  local window_index="$2"

  tmux_cmd list-windows -t "${session}" -F '#{window_index}' 2>/dev/null | grep -Fxq "${window_index}"
}

window_target() {
  local session="$1"
  local window_index="$2"
  printf '%s:%s' "${session}" "${window_index}"
}

restore_window() {
  local session="$1"
  local window_index="$2"
  local key="${session}|${window_index}"
  local target
  local first_path
  local active_pane=""
  local pane_index
  local pane_path
  local current_panes
  local desired_panes

  target="$(window_target "${session}" "${window_index}")"
  first_path="${WINDOW_FIRST_PATH[${key}]:-${HOME}}"
  desired_panes="${WINDOW_PANE_COUNT[${key}]:-1}"

  if ! session_exists "${session}"; then
    tmux_cmd new-session -d -s "${session}" -n "${WINDOW_NAME[${key}]}" -c "${first_path}"
    if [ "${window_index}" != "1" ]; then
      tmux_cmd move-window -s "${session}:1" -t "${target}" >/dev/null 2>&1 || true
    fi
  elif ! window_exists "${session}" "${window_index}"; then
    tmux_cmd new-window -d -t "${target}" -n "${WINDOW_NAME[${key}]}" -c "${first_path}"
  else
    return 0
  fi

  current_panes="$(tmux_cmd list-panes -t "${target}" 2>/dev/null | wc -l | tr -d ' ')"
  for pane_index in ${WINDOW_PANES[${key}]}; do
    if [ "${pane_index}" = "1" ]; then
      continue
    fi
    if [ "${current_panes}" -ge "${desired_panes}" ]; then
      break
    fi
    pane_path="${PANE_PATH[${key}|${pane_index}]:-${first_path}}"
    tmux_cmd split-window -d -t "${target}" -c "${pane_path}"
    current_panes=$((current_panes + 1))
  done

  if [ -n "${WINDOW_LAYOUT[${key}]:-}" ]; then
    tmux_cmd select-layout -t "${target}" "${WINDOW_LAYOUT[${key}]}" >/dev/null 2>&1 || true
  fi

  tmux_cmd rename-window -t "${target}" "${WINDOW_NAME[${key}]}" >/dev/null 2>&1 || true

  for pane_index in ${WINDOW_PANES[${key}]}; do
    if [ "${PANE_ACTIVE[${key}|${pane_index}]:-0}" = "1" ]; then
      active_pane="${pane_index}"
      break
    fi
  done

  if [ -n "${active_pane}" ]; then
    tmux_cmd select-pane -t "${target}.${active_pane}" >/dev/null 2>&1 || true
  fi
}

restore_sessions() {
  local restored_sessions=0
  local restored_windows=0
  local session
  local window_index

  for session in "${SESSION_ORDER[@]}"; do
    if ! session_exists "${session}"; then
      restored_sessions=$((restored_sessions + 1))
    fi

    for window_index in ${SESSION_WINDOWS[${session}]}; do
      if ! window_exists "${session}" "${window_index}"; then
        restored_windows=$((restored_windows + 1))
      fi
      restore_window "${session}" "${window_index}"
    done

    for window_index in ${SESSION_WINDOWS[${session}]}; do
      if [ "${WINDOW_ACTIVE[${session}|${window_index}]:-0}" = "1" ]; then
        tmux_cmd select-window -t "$(window_target "${session}" "${window_index}")" >/dev/null 2>&1 || true
        break
      fi
    done
  done

  notify "Restored ${restored_sessions} sessions and ${restored_windows} windows from tmux snapshot"
}

load_snapshot "${1:-${DEFAULT_SNAPSHOT}}"
restore_sessions
