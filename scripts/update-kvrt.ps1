<#
.SYNOPSIS
    Fetches the latest Kaspersky Virus Removal Tool (KVRT) build metadata and updates bucket/kvrt.json.

.DESCRIPTION
    KVRT is published at an unversioned "latest" URL and rebuilt several times a day, so the
    standard Excavator autoupdate cannot detect new versions. Kaspersky publishes build
    metadata in kvrt.xml (product version + databases_timestamp). This script fetches that
    file - directly and, as a fallback, through the Wayback Machine (web.archive.org/save),
    because devbuilds.s.kaspersky-labs.com returns HTTP 403 to GitHub-hosted runners - and
    stamps the manifest version as "<product version>-<databases_timestamp>", e.g.
    "20.0.14.0-202608100708".

    No hash is pinned on purpose: the "latest" URL content changes far more often than the
    version, so a pinned hash would make updates fail in between workflow runs.

.PARAMETER ManifestPath
    Path to the kvrt manifest. Defaults to <repo>\bucket\kvrt.json.

.PARAMETER XmlUrl
    URL of the kvrt.xml build metadata. Defaults to the Kaspersky devbuilds URL.

.EXAMPLE
    .\scripts\update-kvrt.ps1

.NOTES
    Designed for GitHub Actions (windows-latest, pwsh) and for local runs.
    Writes changed/version outputs to $env:GITHUB_OUTPUT when present.
#>
[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$XmlUrl = 'https://devbuilds.s.kaspersky-labs.com/devbuilds/KVRT/latest/full/kvrt.xml'
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

function Get-KvrtMetadata {
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [int]$TimeoutSeconds = 120
    )
    # Browser-like fingerprint: the server's bot protection may challenge datacenter IPs
    # (e.g. GitHub-hosted runners) otherwise. The cookie jar mirrors the old download flow.
    $tempDir = [System.IO.Path]::GetTempPath()
    $cookieJar = Join-Path $tempDir 'KVRT.cookies.txt'
    $browserUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
    $curlExe = if ($env:OS -eq 'Windows_NT') { 'curl.exe' } else { 'curl' }
    $tmp = Join-Path $tempDir ("kvrt-{0}.xml" -f [guid]::NewGuid().ToString('N'))
    $script:LastHttpStatus = & $curlExe -sL --silent --show-error --max-time $TimeoutSeconds -A $browserUa -c $cookieJar -b $cookieJar --write-out '%{http_code}' --output $tmp $Url 2>$null
    $body = $null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
        $body = [System.IO.File]::ReadAllText($tmp)
    }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if (-not $body) {
        return $null
    }
    $versionMatch = [regex]::Match($body, 'version\s*=\s*"([^"]+)"')
    $stampMatch = [regex]::Match($body, 'databases_timestamp\s*=\s*"([^"]+)"')
    if (-not $versionMatch.Success -or -not $stampMatch.Success) {
        return $null
    }
    return [pscustomobject]@{
        Version = $versionMatch.Groups[1].Value
        Stamp   = $stampMatch.Groups[1].Value
        Source  = $Url
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

# Fetch the build metadata: directly first (fast path), then through the Wayback Machine.
# Kaspersky blocks GitHub-hosted runner IPs with HTTP 403 (intermittently), while
# web.archive.org's /save endpoint re-crawls the URL so the returned content stays fresh.
# Each leg reports its HTTP status so failures are diagnosable from the action log.
$diag = [System.Collections.Generic.List[string]]::new()

$metadata = Get-KvrtMetadata $XmlUrl -TimeoutSeconds 60
$diag.Add("direct: HTTP $script:LastHttpStatus")
if ($metadata) {
    Write-Host "kvrt: metadata fetched directly ($($metadata.Version)-$($metadata.Stamp))"
} else {
    # The /save endpoint is flaky (queue/rate limits): try it up to three times.
    $attempt = 1
    while ($attempt -le 3 -and -not $metadata) {
        Write-Host "kvrt: direct fetch failed, trying the Wayback Machine (attempt $attempt/3)..."
        $metadata = Get-KvrtMetadata ('https://web.archive.org/save/' + $XmlUrl) -TimeoutSeconds 180
        $diag.Add("wayback-save($attempt): HTTP $script:LastHttpStatus")
        if (-not $metadata -and $attempt -lt 3) {
            Start-Sleep -Seconds 10
        }
        $attempt++
    }
}
if (-not $metadata) {
    $metadata = Get-KvrtMetadata ('https://web.archive.org/web/2id_/' + $XmlUrl) -TimeoutSeconds 120
    $diag.Add("wayback-snapshot: HTTP $script:LastHttpStatus")
}
if (-not $metadata) {
    throw "Failed to fetch kvrt.xml from Kaspersky or the Wayback Machine ($XmlUrl). Legs: $($diag -join '; ')"
}

$version = "$($metadata.Version)-$($metadata.Stamp)"

# Update the manifest, preserving formatting (only the version line changes)
$newContent = [regex]::Replace($content, '"version":\s*"[^"]*"', "`"version`": `"$version`"")
if ($newContent -eq $content) {
    Write-Host "kvrt: no changes ($version)"
    Set-OutputValue 'changed' 'false'
    Set-OutputValue 'version' $version
    exit 0
}

[System.IO.File]::WriteAllText($resolvedManifest, $newContent, [System.Text.UTF8Encoding]::new($false))
Write-Host "kvrt: updated to $version (source: $($metadata.Source))"
Set-OutputValue 'changed' 'true'
Set-OutputValue 'version' $version
exit 0
