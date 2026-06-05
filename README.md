# Glitch — downloads

Automatic keyboard language switching for macOS. Glitch is a quiet menu-bar
utility that switches your Mac to the right keyboard **input source** for
whatever app you focus, before you start typing.

**Landing page:** https://tomerast.github.io/glitch-dist/

This repository only hosts the public downloads, installer, and landing page.
The application source lives in a separate private repository.

## Install (recommended)

Paste this into Terminal. It downloads the latest build, verifies its checksum,
installs `Glitch.app` to your Applications folder, clears the unsigned-app
quarantine flag, and enables launch at login:

```sh
curl -fsSL https://raw.githubusercontent.com/tomerast/glitch-dist/main/install.sh | bash
```

## Install manually (DMG)

1. Download the latest `.dmg` from the [Releases page](../../releases/latest).
2. Open it and drag **Glitch** into **Applications**.
3. First launch only: because the build is unsigned, macOS blocks it once. Open
   **System Settings → Privacy & Security**, scroll to the bottom, and click
   **Open Anyway**.

## Requirements

- macOS 14 (Sonoma) or newer.
- Apple Silicon or Intel.
- No account and no paid software required.

## Privacy

Glitch is local by design. In this version:

- No typed text is observed, stored, or displayed.
- No Input Monitoring or Accessibility permission is requested.
- No clipboard access, and no window titles, URLs, document names, or contact
  names are read.
- No network access, telemetry, or update pings.

App rules and aggregate usage are stored locally in
`~/Library/Application Support/Glitch` and are yours to inspect or delete.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/tomerast/glitch-dist/main/uninstall.sh | bash
```

Add `GLITCH_PURGE=1` before the command to also delete local data.

## Note on signing

These are **unsigned, non-notarized private-alpha builds** for testers. Each
release lists a SHA-256 checksum next to its artifacts so you can verify what
you downloaded.
