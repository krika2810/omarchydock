#!/usr/bin/env bash
# Installs the dock to ~/.config/quickshell/dock (keeps your existing pins/size).
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/dock"
dst="$HOME/.config/quickshell/dock"
mkdir -p "$dst"
cp "$src/shell.qml" "$dst/shell.qml"
[ -f "$dst/pinned.json" ] || cp "$src/pinned.example.json" "$dst/pinned.json"
echo "Installed to $dst"
echo "Run now:  quickshell -p $dst/shell.qml"
echo "Autostart: add  exec-once = quickshell -p $dst/shell.qml  to ~/.config/hypr/autostart.conf"
