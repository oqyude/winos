#Requires -Version 5.1
<#
.SYNOPSIS
    Build symlink mappings from a source directory.
.DESCRIPTION
    Scans a directory and produces { from, to } mappings with paths relative
    to the source directory. The output is suitable for inclusion in
    data.json under a symlink entry's "mappings" array.
.PARAMETER Path
    Source directory to scan.
.PARAMETER Recurse
    Include files in subdirectories (default: top-level only).
.PARAMETER IncludeDirectories
    Include directories as mapping entries (default: files only).
.PARAMETER AsJson
    Output as JSON string (default: PowerShell objects).
.PARAMETER SameToFrom
    Mirror each file 1:1 from->to (default). When false, only "from" is set;
    "to" defaults to the same relative path at runtime.
.EXAMPLE
    pwsh -File scripts/build-mappings.ps1 -Path "$persist\AIMP"
.EXAMPLE
    pwsh -File scripts/build-mappings.ps1 -Path "$persist\AIMP" -Recurse -AsJson
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$Recurse,

    [switch]$IncludeDirectories,

    [switch]$AsJson
)

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Source directory not found: $Path"
}

$sourceFull = (Resolve-Path -LiteralPath $Path).Path
$sourceFull = $sourceFull.TrimEnd('\', '/')

$getParams = @{
    Path = $sourceFull
    File = -not $IncludeDirectories
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
