[CmdletBinding()]
param(
    [string]$InstallDirectory = "",
    [string]$DataDirectory = "",
    [switch]$PurgeData,
    [switch]$NoShortcuts
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InstallDirectory = Join-Path $env:LOCALAPPDATA "Programs\Glitch"
}
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = Join-Path $env:LOCALAPPDATA "Glitch"
}

$InstallDirectory = [System.IO.Path]::GetFullPath($InstallDirectory)
$DataDirectory = [System.IO.Path]::GetFullPath($DataDirectory)
$startMenuShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Glitch.lnk"
$startupShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "Glitch.lnk"

function Assert-SafeGlitchPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [System.IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    $profile = [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
    $localAppData = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
    if ($fullPath -eq $root -or $fullPath -eq $profile -or $fullPath -eq $localAppData) {
        throw "refusing unsafe $Purpose path: $fullPath"
    }
    if ([System.IO.Path]::GetFileName($fullPath) -ne "Glitch") {
        throw "$Purpose path must end with a Glitch folder: $fullPath"
    }
}

Assert-SafeGlitchPath -Path $InstallDirectory -Purpose "install"
Assert-SafeGlitchPath -Path $DataDirectory -Purpose "data"

$running = @(Get-Process -Name "Glitch" -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    throw "Glitch is running. Choose Quit from its tray menu, then run the uninstaller again."
}

Write-Host "Uninstalling Glitch for Windows"

if (-not $NoShortcuts) {
    foreach ($shortcut in @($startMenuShortcut, $startupShortcut)) {
        if (Test-Path -LiteralPath $shortcut) {
            Remove-Item -LiteralPath $shortcut -Force
        }
    }
    Write-Host "    removed Glitch shortcuts"
}

if (Test-Path -LiteralPath $InstallDirectory) {
    Remove-Item -LiteralPath $InstallDirectory -Recurse -Force
    Write-Host "    removed $InstallDirectory"
}
else {
    Write-Host "    program folder was already absent"
}

if ($PurgeData) {
    if (Test-Path -LiteralPath $DataDirectory) {
        Remove-Item -LiteralPath $DataDirectory -Recurse -Force
    }
    Write-Host "    removed local data: $DataDirectory"
}
else {
    Write-Host "    kept local data: $DataDirectory"
    Write-Host "    pass -PurgeData to remove profiles, settings, usage counts, and decisions"
}

Write-Host "Glitch has been uninstalled."
