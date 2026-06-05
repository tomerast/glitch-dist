#!/usr/bin/env bash
#
# Glitch uninstaller for macOS.
#
# Quits Glitch, disables launch at login, and removes the app. Local data under
# ~/Library/Application Support/Glitch is kept by default.
#
# One-line uninstall:
#   curl -fsSL https://raw.githubusercontent.com/tomerast/glitch-dist/main/uninstall.sh | bash
#
# Set GLITCH_PURGE=1 to also delete local profiles, usage stats, settings, and
# the decision log (full reset).
#
set -euo pipefail

APP_NAME="Glitch.app"
INSTALLED_APP="/Applications/$APP_NAME"
BUNDLE_ID="com.glitch.keyboardswitcher"
EXECUTABLE="GlitchMac"
AGENT_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
DATA_DIR="$HOME/Library/Application Support/Glitch"

if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; DIM=""; RESET=""
fi
info() { printf '%s==>%s %s\n' "$BOLD$GREEN" "$RESET" "$*"; }
step() { printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }

info "Uninstalling Glitch"

launchctl bootout "gui/$(id -u)/$BUNDLE_ID" >/dev/null 2>&1 || true
rm -f "$AGENT_PLIST"
step "removed launch-at-login agent"

pkill -f "/$APP_NAME/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true
rm -rf "$INSTALLED_APP"
step "removed $INSTALLED_APP"

if [ "${GLITCH_PURGE:-0}" = "1" ]; then
  rm -rf "$DATA_DIR"
  step "removed local data ($DATA_DIR)"
else
  step "kept local data ($DATA_DIR) — set GLITCH_PURGE=1 to delete it"
fi

printf '\n%sGlitch has been uninstalled.%s\n' "$BOLD$GREEN" "$RESET"
