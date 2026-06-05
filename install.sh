#!/usr/bin/env bash
#
# Glitch installer for macOS.
#
# Installs Glitch to /Applications, removes the quarantine flag (the private-alpha
# build is unsigned), enables launch at login, and starts the app.
#
# Testers install with one line (no repo access, no Apple account needed):
#   curl -fsSL https://raw.githubusercontent.com/tomerast/glitch-dist/main/install.sh | bash
#
# It accepts the release in three ways, tried in this order:
#   1. A local .zip you already downloaded:   bash install.sh ~/Downloads/Glitch-*.zip
#   2. The GitHub CLI (for maintainers with source-repo access):
#        GLITCH_REPO=tomerast/glitch gh release download ... | bash
#   3. The public glitch-dist release assets (default path for testers).
#
# Overrides (optional):
#   GLITCH_REPO          GitHub owner/repo          (default: tomerast/glitch-dist)
#   GLITCH_TAG           release tag to install     (default: latest release)
#   GLITCH_ZIP_URL       explicit .zip download URL
#   GLITCH_NO_AUTOSTART=1   skip launch-at-login setup
#
set -euo pipefail

REPO="${GLITCH_REPO:-tomerast/glitch-dist}"
APP_NAME="Glitch.app"
INSTALL_DIR="${GLITCH_INSTALL_DIR:-/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
BUNDLE_ID="com.glitch.keyboardswitcher"
EXECUTABLE="GlitchMac"
AGENT_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
MIN_MACOS_MAJOR=14
LOCAL_ZIP="${1:-}"

if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""
fi
info() { printf '%s==>%s %s\n' "$BOLD$GREEN" "$RESET" "$*"; }
warn() { printf '%s==>%s %s\n' "$BOLD$YELLOW" "$RESET" "$*"; }
step() { printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
die()  { printf '%serror:%s %s\n' "$BOLD$RED" "$RESET" "$*" >&2; exit 1; }

require_macos() {
  [ "$(uname -s)" = "Darwin" ] || die "Glitch only runs on macOS."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  if [ "$major" -lt "$MIN_MACOS_MAJOR" ]; then
    die "Glitch requires macOS $MIN_MACOS_MAJOR (Sonoma) or newer. Found $(sw_vers -productVersion)."
  fi
}

verify_checksum() {
  local zip="$1" sum_file="$1.sha256"
  if [ ! -f "$sum_file" ]; then
    warn "no checksum file found; skipping verification"
    return
  fi
  # Compare hashes directly so verification does not depend on the filename
  # recorded inside the .sha256 file (the asset is renamed during download).
  local expected actual
  expected="$(awk 'NR==1{print $1}' "$sum_file")"
  actual="$(shasum -a 256 "$zip" | awk '{print $1}')"
  if [ -n "$expected" ] && [ "$expected" = "$actual" ]; then
    step "checksum verified"
  else
    die "checksum verification failed for $(basename "$zip")"
  fi
}

# Places a Glitch release zip (and its .sha256 if available) at $1.
acquire_zip() {
  local dest="$1"

  if [ -n "$LOCAL_ZIP" ]; then
    [ -f "$LOCAL_ZIP" ] || die "file not found: $LOCAL_ZIP"
    step "using local archive: $LOCAL_ZIP"
    cp "$LOCAL_ZIP" "$dest"
    [ -f "$LOCAL_ZIP.sha256" ] && cp "$LOCAL_ZIP.sha256" "$dest.sha256"
    return
  fi

  if [ -n "${GLITCH_ZIP_URL:-}" ]; then
    step "downloading: $GLITCH_ZIP_URL"
    curl -fL --progress-bar "$GLITCH_ZIP_URL" -o "$dest" || die "download failed"
    curl -fsSL "$GLITCH_ZIP_URL.sha256" -o "$dest.sha256" 2>/dev/null || true
    return
  fi

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    step "downloading via GitHub CLI from $REPO"
    local ghdir tag
    ghdir="$(dirname "$dest")/gh"
    mkdir -p "$ghdir"
    # `gh release download` with no tag uses the API's "latest", which excludes
    # prereleases; resolve the newest release tag explicitly so alpha prereleases
    # are found.
    tag="${GLITCH_TAG:-$(gh release list --repo "$REPO" --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || true)}"
    [ -n "$tag" ] || die "no releases found in $REPO"
    gh release download "$tag" --repo "$REPO" \
      --pattern '*.zip' --pattern '*.zip.sha256' --dir "$ghdir" --clobber \
      || die "gh release download failed (check repo access and 'gh auth status')"
    local found
    found="$(/bin/ls "$ghdir"/*.zip 2>/dev/null | head -n1 || true)"
    [ -n "$found" ] || die "no .zip asset found in the release"
    mv "$found" "$dest"
    [ -f "$found.sha256" ] && mv "$found.sha256" "$dest.sha256"
    return
  fi

  # Public fallback: resolve newest release asset via the API.
  step "resolving latest public release from $REPO"
  local url
  url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases" \
    | grep -oE '"browser_download_url": *"[^"]+\.zip"' \
    | sed -E 's/.*"(https[^"]+)".*/\1/' | head -n1)"
  [ -n "$url" ] || die "could not find a release asset (private repo? install GitHub CLI 'gh' or pass a local .zip)"
  step "downloading: $url"
  curl -fL --progress-bar "$url" -o "$dest" || die "download failed"
  curl -fsSL "$url.sha256" -o "$dest.sha256" 2>/dev/null || true
}

stop_running() {
  if pgrep -f "/$APP_NAME/Contents/MacOS/$EXECUTABLE" >/dev/null 2>&1; then
    step "quitting running Glitch"
    pkill -f "/$APP_NAME/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true
    sleep 1
  fi
}

install_app() {
  local staged="$1"
  [ -d "$staged/$APP_NAME" ] || die "archive did not contain $APP_NAME at the top level"
  local got
  got="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staged/$APP_NAME/Contents/Info.plist" 2>/dev/null || true)"
  [ "$got" = "$BUNDLE_ID" ] || die "unexpected bundle identifier: ${got:-missing}"

  rm -rf "$INSTALLED_APP"
  ditto "$staged/$APP_NAME" "$INSTALLED_APP"
  step "installed to $INSTALLED_APP"

  xattr -dr com.apple.quarantine "$INSTALLED_APP" 2>/dev/null || true
  step "cleared quarantine flag (unsigned alpha build)"
}

enable_autostart() {
  if [ "${GLITCH_NO_AUTOSTART:-0}" = "1" ]; then
    warn "skipping launch-at-login (GLITCH_NO_AUTOSTART=1)"
    return
  fi
  mkdir -p "$(dirname "$AGENT_PLIST")"
  cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALLED_APP/Contents/MacOS/$EXECUTABLE</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST

  local domain="gui/$(id -u)"
  launchctl bootout "$domain/$BUNDLE_ID" >/dev/null 2>&1 || true
  launchctl bootstrap "$domain" "$AGENT_PLIST" >/dev/null 2>&1 \
    || die "failed to register launch-at-login agent"
  launchctl enable "$domain/$BUNDLE_ID" >/dev/null 2>&1 || true
  step "enabled launch at login"
}

start_app() {
  local domain="gui/$(id -u)"
  if [ "${GLITCH_NO_AUTOSTART:-0}" != "1" ]; then
    launchctl kickstart -k "$domain/$BUNDLE_ID" >/dev/null 2>&1 || open "$INSTALLED_APP"
  else
    open "$INSTALLED_APP"
  fi
}

main() {
  info "Installing Glitch"
  require_macos

  # workdir is intentionally global so the EXIT trap can clean it up after main
  # returns (a function-local would be out of scope and trip `set -u`).
  workdir="$(mktemp -d)"
  trap 'rm -rf "${workdir:-}"' EXIT
  local zip="$workdir/glitch.zip"

  info "Getting the release"
  acquire_zip "$zip"
  verify_checksum "$zip"

  info "Installing the app"
  stop_running
  ditto -x -k "$zip" "$workdir/extracted"
  install_app "$workdir/extracted"

  info "Configuring startup"
  enable_autostart
  start_app

  printf '\n%sGlitch is installed and running.%s\n' "$BOLD$GREEN" "$RESET"
  printf 'Look for the Glitch icon in your menu bar (top-right). It has no Dock icon.\n'
  [ "${GLITCH_NO_AUTOSTART:-0}" != "1" ] && printf 'It will start automatically when you log in.\n'
  printf '%sTo uninstall later, run scripts/uninstall.sh from the repo (or the release asset).%s\n' "$DIM" "$RESET"
}

main "$@"
