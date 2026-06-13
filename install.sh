#!/usr/bin/env bash

set -e
set -u
set -o pipefail

is_app_installed() {
  type "$1" &>/dev/null
}

log() {
  printf '%s\n' "$1"
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

REPODIR="$(cd "$(dirname "$0")"; pwd -P)"
cd "$REPODIR";

if ! is_app_installed tmux; then
  fail "\"tmux\" command is not found. Install tmux >= 3.5 first."
fi

if ! is_app_installed git; then
  fail "\"git\" command is not found. Install git first."
fi

mkdir -p "$HOME/.tmux" "$HOME/.tmux/plugins" "$HOME/.tmux/snapshots"

if [ ! -e "$HOME/.tmux/plugins/tpm" ]; then
  log "TPM not found at \$HOME/.tmux/plugins/tpm. Cloning it now."
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm \
    || fail "failed to clone TPM into \$HOME/.tmux/plugins/tpm"
fi

if [ -e "$HOME/.tmux.conf" ]; then
  log "Found existing .tmux.conf in your \$HOME directory. Backing it up to $HOME/.tmux.conf.bak"
fi

cp -f "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak" 2>/dev/null || true
for file in \
  renew_env.sh \
  session_restore.sh \
  session_snapshot.sh \
  tmux.conf \
  tmux.base.conf \
  tmux.theme.conf \
  tmux.plugins.conf \
  tmux.nesting.conf \
  tmux.remote.conf \
  tmux.local.conf.example \
  yank.sh; do
  if [ -e "$HOME/.tmux/$file" ] || [ -L "$HOME/.tmux/$file" ]; then
    rm -f "$HOME/.tmux/$file"
  fi
  ln -sf "$REPODIR/tmux/$file" "$HOME/.tmux/$file"
done
ln -sf .tmux/tmux.conf "$HOME"/.tmux.conf;

# Install TPM plugins.
# TPM requires running tmux server, as soon as `tmux start-server` does not work
# create dump __noop session in detached mode, and kill it when plugins are installed
log "Installing TPM plugins"
tmux new -d -s __noop >/dev/null 2>&1 || true 
tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "~/.tmux/plugins"
"$HOME"/.tmux/plugins/tpm/bin/install_plugins \
  || fail "TPM plugin installation failed"
tmux kill-session -t __noop >/dev/null 2>&1 || true

if tmux list-sessions >/dev/null 2>&1; then
  log "Reloading running tmux server"
  tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1 || true
  log "NOTE: If you are migrating from the old continuum/resurrect setup and still see 'Restoring...', run: tmux kill-server"
fi

log "OK: Completed"
