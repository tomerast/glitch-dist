[CmdletBinding()]
param(
    [string]$ZipPath = "",
    [string]$ChecksumPath = "",
    [string]$InstallDirectory = "",
    [string]$ReleaseBaseUrl = "https://github.com/tomerast/glitch-dist/releases/latest/download",
    [switch]$NoStartup,
    [switch]$NoLaunch,
    [switch]$NoShortcuts,
    [switch]$RequireSigned
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$appName = "Glitch"
$executableName = "Glitch.exe"
$stableArchiveName = "Glitch-Windows-x64.zip"
$defaultInstallDirectory = Join-Path $env:LOCALAPPDATA "Programs\Glitch"
$startMenuShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Glitch.lnk"
$startupShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "Glitch.lnk"

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InstallDirectory = $defaultInstallDirectory
}
$InstallDirectory = [System.IO.Path]::GetFullPath($InstallDirectory)

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "    $Message"
}

function Assert-Windows11 {
    if ($PSVersionTable.PSEdition -eq "Core" -and -not $IsWindows) {
        throw "Glitch Windows can only be installed on Windows."
    }

    $version = [System.Environment]::OSVersion.Version
    if ($version.Major -lt 10 -or $version.Build -lt 22000) {
        throw "Glitch requires Windows 11 (build 22000 or newer). Found $version."
    }
}

function Assert-SafeInstallDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [System.IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    $profile = [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
    $localAppData = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')

    if ($fullPath -eq $root -or $fullPath -eq $profile -or $fullPath -eq $localAppData) {
        throw "refusing unsafe install directory: $fullPath"
    }
    if ([System.IO.Path]::GetFileName($fullPath) -ne "Glitch") {
        throw "install directory must end with a Glitch folder: $fullPath"
    }
}

function Get-ExpectedChecksum {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "required checksum file not found: $Path"
    }
    $line = (Get-Content -LiteralPath $Path -Raw).Trim()
    $value = ($line -split "\s+")[0].ToLowerInvariant()
    if ($value -notmatch "^[0-9a-f]{64}$") {
        throw "checksum file does not start with a valid SHA-256 digest: $Path"
    }
    return $value
}

function Test-ArchiveChecksum {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DigestPath
    )

    $expected = Get-ExpectedChecksum -Path $DigestPath
    $actual = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "checksum verification failed: expected $expected, got $actual"
    }
    Write-Step "archive corruption check passed (SHA-256: $actual)"
}

function Get-PackageRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination
    $entries = @(Get-ChildItem -LiteralPath $Destination -Force)
    if ($entries.Count -ne 1 -or -not $entries[0].PSIsContainer) {
        throw "Glitch archive must contain exactly one top-level package directory."
    }

    $packageRoot = $entries[0].FullName
    $requiredFiles = @("Glitch.exe", "RELEASE-NOTES.md", "LICENSE.txt", "BUILD-INFO.txt")
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $file) -PathType Leaf)) {
            throw "Glitch archive is missing required file: $file"
        }
    }

    $files = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse)
    if ($files.Count -ne $requiredFiles.Count) {
        throw "Glitch archive contains unexpected files."
    }
    $executables = @($files | Where-Object { $_.Extension -ieq ".exe" })
    if ($executables.Count -ne 1 -or $executables[0].Name -ne $executableName) {
        throw "Glitch.exe must be the package's only executable."
    }
    return $packageRoot
}

function Test-ExecutableTrust {
    param([Parameter(Mandatory = $true)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -eq "Valid") {
        Write-Step "valid Authenticode signature: $($signature.SignerCertificate.Subject)"
        return "signed"
    }
    if ($signature.Status -ne "NotSigned") {
        throw "Glitch.exe has an invalid Authenticode status: $($signature.Status)"
    }
    if ($RequireSigned) {
        throw "this Glitch build is unsigned; -RequireSigned refuses to install it"
    }

    Write-Warning "This private-alpha build is unsigned. Windows may show a SmartScreen warning."
    Write-Warning "The installer will not disable or bypass Windows security protections."
    return "unsigned"
}

function Assert-GlitchStopped {
    $running = @(Get-Process -Name "Glitch" -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw "Glitch is running. Choose Quit from its tray menu, then run the installer again."
    }
}

function New-Shortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    $shortcut.WorkingDirectory = Split-Path -Parent $Target
    $shortcut.Description = "Glitch keyboard language switching"
    $shortcut.Save()
}

Assert-Windows11
Assert-SafeInstallDirectory -Path $InstallDirectory

$workDirectory = Join-Path $env:TEMP ("glitch-windows-install-" + [System.Guid]::NewGuid().ToString("N"))
$downloadedArchive = Join-Path $workDirectory $stableArchiveName
$downloadedChecksum = "$downloadedArchive.sha256"
$extractDirectory = Join-Path $workDirectory "extracted"
$stageDirectory = "$InstallDirectory.stage-$([System.Guid]::NewGuid().ToString('N'))"
$backupDirectory = "$InstallDirectory.backup-$([System.Guid]::NewGuid().ToString('N'))"

New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

try {
    Write-Host "Installing Glitch for Windows"

    if ([string]::IsNullOrWhiteSpace($ZipPath)) {
        $archiveUrl = "$($ReleaseBaseUrl.TrimEnd('/'))/$stableArchiveName"
        $checksumUrl = "$archiveUrl.sha256"
        Write-Step "downloading $archiveUrl"
        Invoke-WebRequest -Uri $archiveUrl -OutFile $downloadedArchive
        Invoke-WebRequest -Uri $checksumUrl -OutFile $downloadedChecksum
        $ZipPath = $downloadedArchive
        $ChecksumPath = $downloadedChecksum
    }
    else {
        $ZipPath = [System.IO.Path]::GetFullPath($ZipPath)
        if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
            throw "archive not found: $ZipPath"
        }
        if ([string]::IsNullOrWhiteSpace($ChecksumPath)) {
            $ChecksumPath = "$ZipPath.sha256"
        }
        else {
            $ChecksumPath = [System.IO.Path]::GetFullPath($ChecksumPath)
        }
        Write-Step "using local archive: $ZipPath"
    }

    Test-ArchiveChecksum -ArchivePath $ZipPath -DigestPath $ChecksumPath
    $packageRoot = Get-PackageRoot -ArchivePath $ZipPath -Destination $extractDirectory
    $trust = Test-ExecutableTrust -Path (Join-Path $packageRoot $executableName)
    Assert-GlitchStopped

    $installParent = Split-Path -Parent $InstallDirectory
    New-Item -ItemType Directory -Path $installParent -Force | Out-Null
    Copy-Item -LiteralPath $packageRoot -Destination $stageDirectory -Recurse

    if (Test-Path -LiteralPath $InstallDirectory) {
        Move-Item -LiteralPath $InstallDirectory -Destination $backupDirectory
    }
    try {
        Move-Item -LiteralPath $stageDirectory -Destination $InstallDirectory
    }
    catch {
        if (Test-Path -LiteralPath $backupDirectory) {
            Move-Item -LiteralPath $backupDirectory -Destination $InstallDirectory
        }
        throw
    }
    if (Test-Path -LiteralPath $backupDirectory) {
        Remove-Item -LiteralPath $backupDirectory -Recurse -Force
    }

    $installedExecutable = Join-Path $InstallDirectory $executableName
    if (-not $NoShortcuts) {
        New-Shortcut -Path $startMenuShortcut -Target $installedExecutable
        Write-Step "created Start Menu shortcut"
        if (-not $NoStartup) {
            New-Shortcut -Path $startupShortcut -Target $installedExecutable
            Write-Step "enabled launch at sign-in"
        }
        elseif (Test-Path -LiteralPath $startupShortcut) {
            Remove-Item -LiteralPath $startupShortcut -Force
        }
    }

    if (-not $NoLaunch) {
        Start-Process -FilePath $installedExecutable
    }

    Write-Host ""
    Write-Host "Glitch is installed."
    Write-Host "  Program: $InstallDirectory"
    Write-Host "  Local data: $(Join-Path $env:LOCALAPPDATA 'Glitch')"
    Write-Host "  Signature: $trust"
    if ($trust -eq "unsigned") {
        Write-Host "  Security: Windows protections were left enabled; follow any SmartScreen prompt explicitly."
    }
}
finally {
    foreach ($temporaryPath in @($stageDirectory, $workDirectory)) {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Recurse -Force
        }
    }
}
