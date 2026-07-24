#Requires -Version 5.1
<#
.SYNOPSIS
    Build symlink mappings from a source directory.
.DESCRIPTION
    Scans a directory and produces { from, to } mappings with paths relative
    to the source directory. The output is suitable for inclusion in
    data.json under a symlink entry's "mappings" array.

    By default, both files AND directories are included, since "contents of
    a directory" naturally includes subdirectories. Use -FilesOnly to only
    include files.
.PARAMETER Path
    Source directory to scan.
.PARAMETER Recurse
    Include files in subdirectories (default: top-level only).
.PARAMETER FilesOnly
    Include only files (default: files AND directories).
.PARAMETER AsJson
    Output as JSON string (default: PowerShell objects).
.EXAMPLE
    pwsh -File scripts/build-mappings.ps1 -Path "$persist\AIMP"
.EXAMPLE
    pwsh -File scripts/build-mappings.ps1 -Path "$persist\AIMP" -Recurse -AsJson
.EXAMPLE
    pwsh -File scripts/build-mappings.ps1 -Path "$persist\AIMP" -FilesOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$Recurse,

    [switch]$FilesOnly,

    [switch]$AsJson
)

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Source directory not found: $Path"
}

$sourceFull = (Resolve-Path -LiteralPath $Path).Path
$sourceFull = $sourceFull.TrimEnd('\', '/')

$getParams = @{
    Path = $sourceFull
    File = [bool]$FilesOnly
}
if ($Recurse) { $getParams.Recurse = $true }

$items = Get-ChildItem @getParams -ErrorAction SilentlyContinue

$mappings = foreach ($item in $items) {
    # Compute path relative to source (forward slashes for consistency)
    $relative = $item.FullName.Substring($sourceFull.Length).TrimStart('\', '/') -replace '\\', '/'
    [PSCustomObject]@{
        from = $relative
        to   = $relative
    }
}

if ($AsJson) {
    @($mappings) | ConvertTo-Json -Depth 3 -Compress
} else {
    $mappings
}
