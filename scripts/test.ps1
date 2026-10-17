<#
.SYNOPSIS
    Run the Pester test suite under tests/.

.DESCRIPTION
    Single .CI entry point for the test suite.

    Uses the repo's installed Pester via New-PesterConfiguration, which needs
    Pester 5.0+. Pester prints its own summary; this wrapper prints the banner
    and the exit contract on top.

    Exits 0 only when every test passes and Pester reports no execution errors.
    Exits 1 when any test fails, when Pester reports an error not attributable to
    a specific test (e.g. a missing test file), or when Pester is not installed
    at all.

    The previous version of this script called `Invoke-Pester` with no gate at
    all, so it returned exit 0 even when tests were failing -- CI built on it
    could never go red. That is not a theoretical concern: this repo shipped
    v0.1.2 while a test still asserted v0.1.0, and the suite was reported green.

.EXAMPLE
    pwsh -NoProfile -File .\scripts\test.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Anchor to $PSScriptRoot so the script behaves identically whether invoked as
# `pwsh -File .\scripts\test.ps1` from any cwd, or `.\scripts\test.ps1` from a
# session that started elsewhere.
$repoRoot = Split-Path -Parent $PSScriptRoot
$testPath = Join-Path $repoRoot 'tests'

if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Warning 'Pester is not installed.'
    Write-Warning 'Install it with: Install-Module Pester -Scope CurrentUser'
    exit 1
}

Import-Module Pester

if (-not (Test-Path -LiteralPath $testPath)) {
    # A missing tests/ tree is a checkout problem, not a passing build.
    Write-Warning "Tests directory not found: $testPath"
    exit 1
}

Write-Host ''
Write-Host '  winos :: test'
Write-Host ('  ' + ('-' * 32))
Write-Host ''

# PassThru yields the Run object, which is what the exit contract is gated on;
# without it Invoke-Pester returns nothing useful on success.
$cfg = New-PesterConfiguration
$cfg.Run.Path       = $testPath
$cfg.Run.PassThru   = $true
$cfg.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $cfg

# Two independent failure signals: a failing test, and an error that never
# surfaces as a failed test (a Discovery-phase exception, say). Either one must
# fail the build.
$failedCount = if ($null -ne $result) { $result.FailedCount } else { 1 }
$hadErrors   = ($null -ne $result) -and [bool]$result.HadErrors

if ($failedCount -gt 0 -or $hadErrors) {
    Write-Host ''
    Write-Host ("    result: {0} failed, {1} passed, had errors: {2}" -f $failedCount, $result.PassedCount, $hadErrors) -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host ("    result: {0} passed, 0 failed" -f $result.PassedCount) -ForegroundColor Green
exit 0