#!/bin/bash
###############################################################################
# install.sh — copy the versioned hooks in this directory into .git/hooks.
#
# Git does not version .git/hooks and this repo deliberately does not set
# core.hooksPath, so each checkout installs the hooks once:
#
#   ./githooks/install.sh
#
# Re-run after pulling a change to any hook.
###############################################################################
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$(git -C "$SRC" rev-parse --absolute-git-dir)/hooks"
mkdir -p "$DST"

for hook in pre-commit; do
    install -m 755 "$SRC/$hook" "$DST/$hook"
    echo "installed $hook -> $DST/$hook"
done
