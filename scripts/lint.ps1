<#
.SYNOPSIS
    Run PSScriptAnalyzer across src, tests and scripts.

.DESCRIPTION
    Single .CI entry point for static analysis.

    Prints a per-tree finding count and a total, lists every finding with its
    severity, file, line and rule, and exits non-zero when the total is above
    zero -- or when a tree is missing, or when the module itself is absent. A
    linter that silently passes when the tool is missing is worse than no
    linter, because it reports "clean" for a checkout it never examined.

.EXAMPLE
    pwsh -NoProfile -File .\scripts\lint.ps1

.NOTES
    Scope note: this script reads .pspsscriptanalyzer.psd1 and does not modify
    it. Which rules are excluded is a project decision, not a tooling one --
    see task W8 in .agent/tasks/manifest.json for the open question about the
    three rules that the transferred plugin module deliberately violates.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Anchor to $PSScriptRoot so the script behaves identically from any cwd.
$repoRoot     = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $repoRoot '.pspsscriptanalyzer.psd1'
$trees        = @('src', 'tests', 'scripts')

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Warning 'PSScriptAnalyzer is not installed.'
    Write-Warning 'Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser'
    exit 1
}

Import-Module PSScriptAnalyzer

if (-not (Test-Path -LiteralPath $settingsPath)) {
    # Falling back to defaults would make this script disagree with the editor's
    # findings. That drift is exactly what a lint step exists to prevent.
    Write-Warning "Settings file not found: $settingsPath"
    exit 1
}

Write-Host ''
Write-Host '  winos :: lint'
Write-Host ('  ' + ('-' * 32))
Write-Host ''

# A finding in any tree fails the run. Treating trees independently would let a
# regression in tests slip through because src and scripts happened to be clean.
$total = 0
foreach ($tree in $trees) {
    $path = Join-Path $repoRoot $tree
    if (-not (Test-Path -LiteralPath $path)) {
        # A missing tree counts as a problem, not a pass: these three are core
        # to the repo, and "clean" about an incomplete checkout is a lie.
        Write-Warning "Missing tree: $path"
        $total++
        continue
    }

    $findings = Invoke-ScriptAnalyzer -Path $path -Settings $settingsPath -Recurse -ErrorAction SilentlyContinue
    $count    = @($findings).Count
    $total   += $count

    $color = if ($count -gt 0) { 'Red' } else { 'Green' }
    Write-Host ("    {0,-8} {1,4} finding(s)" -f $tree, $count) -ForegroundColor $color

    foreach ($f in $findings) {
        $rel = $f.ScriptPath.Substring($repoRoot.Length).TrimStart('\', '/')
        Write-Host ("      [{0,-7}] {1}:{2}  {3}  ({4})" -f $f.Severity, $rel, $f.Line, $f.Message, $f.RuleName) -ForegroundColor Yellow
    }
}

Write-Host ''
$summaryColor = if ($total -gt 0) { 'Red' } else { 'Green' }
Write-Host ("    total: {0}" -f $total) -ForegroundColor $summaryColor
Write-Host ''

if ($total -gt 0) { exit 1 }
exit 0