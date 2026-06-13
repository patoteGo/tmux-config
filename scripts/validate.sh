#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.."; pwd -P)"

cd "${REPO_DIR}"

bash -n install.sh \
  tmux/renew_env.sh \
  tmux/session_restore.sh \
  tmux/session_snapshot.sh \
  tmux/yank.sh

echo "Shell syntax OK"

