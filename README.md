# Glitch — downloads

Automatic keyboard language switching for macOS and Windows. Glitch notices
which app is active and switches to that app's learned or manual input-language
profile before you type.

**Landing page:** https://tomerast.github.io/glitch-dist/

This public repository hosts downloads, installers, and the landing page. The
application source lives in a separate repository.

## macOS 14+

Install from Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/tomerast/glitch-dist/main/install.sh | bash
```

Or download `Glitch-macOS.dmg` from the
[latest release](../../releases/latest), open it, and drag Glitch into
Applications.

The private-alpha build is unsigned and not notarized. The installer requires
the adjacent SHA-256 file and leaves Gatekeeper and quarantine protections
unchanged. If macOS blocks first launch, use the explicit **Open Anyway** action
under **System Settings → Privacy & Security**.

## Windows 11

Install per-user from Windows PowerShell or PowerShell 7:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/tomerast/glitch-dist/main/install-windows.ps1)))
```

Or download `Glitch-Windows-x64.zip` and its `.sha256` file from the
[latest release](../../releases/latest), then run the public installer against
the local ZIP.

The Windows installer:

- requires a matching SHA-256 corruption check;
- validates the package structure and Authenticode status;
- installs under `%LOCALAPPDATA%\Programs\Glitch` without administrator access;
- creates Start Menu and launch-at-sign-in shortcuts;
- preserves `%LOCALAPPDATA%\Glitch` during updates and normal uninstall;
- never invokes `Unblock-File`, changes execution policy, or suppresses
  SmartScreen.

The current Windows build is unsigned. Follow any Windows security prompt
explicitly and install only if you trust this private-alpha source.

## Privacy

Both builds are local by design:

- No typed text is observed, stored, or displayed.
- No keyboard hook is installed on Windows; macOS requests no Input Monitoring.
- No clipboard content, window titles, URLs, document names, contact names, or
  app content are read.
- Normal app operation requires no server, telemetry, or update check.

## Uninstall

macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/tomerast/glitch-dist/main/uninstall.sh | bash
```

Use `GLITCH_PURGE=1` to also delete macOS local data.

Windows PowerShell or PowerShell 7:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/tomerast/glitch-dist/main/uninstall-windows.ps1)))
```

Download and run `uninstall-windows.ps1 -PurgeData` when a full Windows data
reset is intended.

## Integrity and signing

The adjacent SHA-256 files detect incomplete or corrupted downloads. Because
they are hosted beside the artifacts, they are not an independent signature or
protection against a compromised release host. Missing or mismatched checksums
are fatal to both installers.

The current private-alpha builds are unsigned. The installers do not disable
operating-system security controls. Normal public distribution still requires
Developer ID signing/notarization on macOS and Authenticode signing on Windows.
