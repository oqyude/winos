<#
.SYNOPSIS
    Fetches the latest Kaspersky Virus Removal Tool (KVRT) build and updates bucket/kvrt.json.

.DESCRIPTION
    KVRT is published at an unversioned "latest" URL and rebuilt several times a day, so the
    standard Excavator autoupdate cannot detect new versions (scoop would also never flag a
    "nightly" manifest as outdated unless UPDATE_NIGHTLY is enabled). This script:
      1. Reads the Last-Modified header to detect whether the remote build changed.
      2. If the build is unchanged, skips the 121 MB download and exits.
      3. Otherwise downloads KVRT.exe, reads its FileVersion and stamps the build time into
         the version, e.g. "20.0.14.0-202608061709", then rewrites the manifest's version line.

    The Last-Modified header is only an optimization: some networks (e.g. GitHub-hosted
    runners) do not return it for HEAD requests. When it is missing, the stamp is taken from
    the download response headers or, as a last resort, from the download time.

    The Last-Modified header is only an optimization: some networks (e.g. GitHub-hosted
    runners) may not return it or may challenge the request. The download therefore mimics a
    browser (User-Agent, cookie jar) and retries once after the server's bot-protection
    cookie handshake. When no Last-Modified is available, the stamp falls back to the
    download time.

    No hash is pinned on purpose: the "latest" URL content changes far more often than the
    FileVersion, so a pinned hash would make updates fail in between workflow runs.

.PARAMETER ManifestPath
    Path to the kvrt manifest. Defaults to <repo>\bucket\kvrt.json.

.PARAMETER KvrtUrl
    KVRT download URL. Defaults to the Kaspersky devbuilds "latest" URL.

.PARAMETER Force
    Skip the Last-Modified fast check and always download, even if the build stamp is unchanged.

.EXAMPLE
    .\scripts\update-kvrt.ps1

.NOTES
    Designed for GitHub Actions (windows-latest, pwsh) and for local runs.
    Writes changed/version outputs to $env:GITHUB_OUTPUT when present.
#>
[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$KvrtUrl = 'https://devbuilds.s.kaspersky-labs.com/devbuilds/KVRT/latest/full/KVRT.exe',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# $PSScriptRoot can be empty in the param() block when invoked via -File with a
# relative path (PowerShell 5.1), so resolve the default here instead.
if (-not $ManifestPath) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    $ManifestPath = Join-Path $scriptRoot '..\bucket\kvrt.json'
}
if ($env:KVRT_URL) {
    $KvrtUrl = $env:KVRT_URL
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

function Get-BuildStamp {
    param([string[]]$Lines)
    $line = $Lines | Where-Object { $_ -match '^Last-Modified:' } | Select-Object -Last 1
    if (-not $line) {
        return $null
    }
    $value = ($line -replace '^Last-Modified:\s*', '').Trim()
    try {
        $parsed = [datetime]::ParseExact(
            $value,
            'r',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        )
        return $parsed.ToUniversalTime().ToString('yyyyMMddHHmm')
    } catch {
        return $null
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

# Browser-like fingerprint: the server's bot protection sets a klid cookie and may
# challenge datacenter IPs (e.g. GitHub-hosted runners) otherwise.
$cookieJar = Join-Path $env:TEMP 'KVRT.cookies.txt'
$browserUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

# Fast path: detect build changes via the Last-Modified header (avoids the 121 MB download).
# The header may be absent on some networks, in which case we fall through to the download.
$remoteStamp = $null
if (-not $Force) {
    $headers = & curl.exe -sI --max-time 30 -A $browserUa -c $cookieJar -b $cookieJar $KvrtUrl 2>$null
    $remoteStamp = Get-BuildStamp $headers
    if ($remoteStamp -and $remoteStamp -eq $currentStamp) {
        Write-Host "kvrt: build unchanged ($remoteStamp), nothing to do"
        Remove-Item $cookieJar -Force -ErrorAction SilentlyContinue
        Set-OutputValue 'changed' 'false'
        Set-OutputValue 'version' $currentVersion
        exit 0
    }
}

# Download and read the real product version, keeping the response headers for the build stamp
$kvrtExe = Join-Path $env:TEMP 'KVRT.exe'
$headerDump = Join-Path $env:TEMP 'KVRT.headers.txt'
$curlArgs = @(
    '-L', '--fail', '--silent', '--show-error',
    '--retry', '2', '--retry-delay', '2',
    '-A', $browserUa,
    '-c', $cookieJar, '-b', $cookieJar,
    '--write-out', '%{http_code}',
    '--max-time', '900',
    '--dump-header', $headerDump,
    '--output', $kvrtExe,
    $KvrtUrl
)

$httpStatus = & curl.exe @curlArgs 2>$null
if ($LASTEXITCODE -ne 0) {
    # Retry once: the bot protection may require the cookie it set in the failed response
    $httpStatus = & curl.exe @curlArgs 2>$null
}
if ($LASTEXITCODE -ne 0) {
    $bodySample = ''
    if ((Test-Path $kvrtExe) -and ((Get-Item $kvrtExe).Length -lt 10000)) {
        try {
            $bodyText = ([string](Get-Content $kvrtExe -Raw -ErrorAction Stop)) -replace '\s+', ' '
            $bodySample = ' body: ' + $bodyText.Substring(0, [Math]::Min(150, $bodyText.Length))
        } catch {
            $bodySample = ''
        }
    }
    throw "Failed to download KVRT (HTTP $httpStatus, curl exit $LASTEXITCODE)$bodySample"
}

try {
    $fileVersion = (Get-Item $kvrtExe).VersionInfo.FileVersion
    $buildStamp = Get-BuildStamp ([System.IO.File]::ReadAllLines($headerDump))
    if (-not $buildStamp) {
        $buildStamp = (Get-Item $kvrtExe).LastWriteTime.ToUniversalTime().ToString('yyyyMMddHHmm')
        Write-Warning "Last-Modified header unavailable, using download time ($buildStamp)"
    }
} finally {
    Remove-Item $kvrtExe, $headerDump, $cookieJar -Force -ErrorAction SilentlyContinue
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
