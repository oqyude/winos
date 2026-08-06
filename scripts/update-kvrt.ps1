<#
.SYNOPSIS
    Fetches the latest Kaspersky Virus Removal Tool (KVRT) build and updates bucket/kvrt.json.

.DESCRIPTION
    KVRT is published at an unversioned "latest" URL and rebuilt almost daily, so the standard
    Excavator autoupdate cannot detect new versions (scoop would also never flag a "nightly"
    manifest as outdated unless UPDATE_NIGHTLY is enabled). This script:
      1. Reads the Last-Modified header to detect whether the remote build changed.
      2. If the build is unchanged, skips the 121 MB download and exits.
      3. Otherwise downloads KVRT.exe, reads its FileVersion and stamps the build time into
         the version, e.g. "20.0.14.0-202608060507", then rewrites the manifest's version line.

    No hash is pinned on purpose: the "latest" URL content changes far more often than the
    FileVersion, so a pinned hash would make updates fail in between workflow runs.

.PARAMETER ManifestPath
    Path to the kvrt manifest. Defaults to <repo>\bucket\kvrt.json.

.PARAMETER KvrtUrl
    KVRT download URL. Defaults to the Kaspersky devbuilds "latest" URL.

.EXAMPLE
    .\scripts\update-kvrt.ps1

.NOTES
    Designed for GitHub Actions (windows-latest, pwsh) and for local runs.
    Writes changed/version outputs to $env:GITHUB_OUTPUT when present.
#>
[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$KvrtUrl = 'https://devbuilds.s.kaspersky-labs.com/devbuilds/KVRT/latest/full/KVRT.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# $PSScriptRoot can be empty in the param() block when invoked via -File with a
# relative path (PowerShell 5.1), so resolve the default here instead.
if (-not $ManifestPath) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    $ManifestPath = Join-Path $scriptRoot '..\bucket\kvrt.json'
}

function Set-OutputValue {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Value
    )
    if ($env:GITHUB_OUTPUT) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding ascii
    }
}

$resolvedManifest = [System.IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path $resolvedManifest)) {
    throw "Manifest not found: $resolvedManifest"
}

# Read the current version from the manifest
$content = [System.IO.File]::ReadAllText($resolvedManifest)
$versionMatch = [regex]::Match($content, '"version":\s*"([^"]+)"')
if (-not $versionMatch.Success) {
    throw "Cannot find a version field in $resolvedManifest"
}
$currentVersion = $versionMatch.Groups[1].Value
$currentStamp = if ($currentVersion -match '-(\d{12})$') { $Matches[1] } else { $null }

# Detect build changes via the Last-Modified header (cheap, avoids the 121 MB download)
$headers = & curl.exe -sI --max-time 30 $KvrtUrl
$lastModifiedLine = $headers | Where-Object { $_ -match '^Last-Modified:' } | Select-Object -First 1
if (-not $lastModifiedLine) {
    throw "Last-Modified header not found for $KvrtUrl"
}
$lastModifiedValue = ($lastModifiedLine -replace '^Last-Modified:\s*', '').Trim()
$lastModified = [datetime]::ParseExact(
    $lastModifiedValue,
    'r',
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::AssumeUniversal
)
$buildStamp = $lastModified.ToUniversalTime().ToString('yyyyMMddHHmm')

if ($currentStamp -eq $buildStamp) {
    Write-Host "kvrt: build unchanged ($buildStamp), nothing to do"
    Set-OutputValue 'changed' 'false'
    Set-OutputValue 'version' $currentVersion
    exit 0
}

# Download and read the real product version
$kvrtExe = Join-Path $env:TEMP 'KVRT.exe'
& curl.exe -L --fail --silent --show-error --max-time 600 --output $kvrtExe $KvrtUrl
if ($LASTEXITCODE -ne 0) {
    throw "Failed to download KVRT (curl exit code $LASTEXITCODE)"
}

try {
    $fileVersion = (Get-Item $kvrtExe).VersionInfo.FileVersion
} finally {
    Remove-Item $kvrtExe -Force -ErrorAction SilentlyContinue
}
if ([string]::IsNullOrWhiteSpace($fileVersion)) {
    throw 'Failed to read FileVersion from the downloaded KVRT.exe'
}

$version = "$fileVersion-$buildStamp"

# Update the manifest, preserving formatting (only the version line changes)
$newContent = [regex]::Replace($content, '"version":\s*"[^"]*"', "`"version`": `"$version`"")
if ($newContent -eq $content) {
    Write-Host "kvrt: no changes ($version)"
    Set-OutputValue 'changed' 'false'
    Set-OutputValue 'version' $version
    exit 0
}

[System.IO.File]::WriteAllText($resolvedManifest, $newContent, [System.Text.UTF8Encoding]::new($false))
Write-Host "kvrt: updated to $version (build $buildStamp)"
Set-OutputValue 'changed' 'true'
Set-OutputValue 'version' $version
exit 0
