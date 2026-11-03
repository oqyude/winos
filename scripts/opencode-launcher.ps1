<#
.SYNOPSIS
    The launcher of the opencode server: where it lives, whether a second
    one is lying around, and how it is installed.

.DESCRIPTION
    The launcher used to live in the profile of the user (~/opencode-serve.sh
    on one host, ~/.local/bin/oc-serve-task.sh on another), and each host
    had its own mechanism: one read ~/.bashrc and leaned on an alias, the
    other did not. Two mechanisms for one job is how a server ends up
    without a proxy, or with a log nobody can find.

    The launcher is now part of the machine state:

        <data root>\tools\host-scripts\opencode-serve.sh
        <data root>\tools\host-scripts\opencode-serve.cmd

    The template lives in the repository (src/host-scripts) and is copied
    there by the installer. The functions here are the pure half of that:
    they look at the disk and return facts, and the tests drive them
    without a Windows host and without a live server.

.NOTES
    Pure ASCII on purpose: this file travels over ssh to the Windows hosts.
#>

# The files that make up the launcher. The .cmd is the Windows face of the
# .sh; both are installed together, because a .cmd without a .sh is a
# wrapper around nothing.
$OpenCodeLauncherFiles = @(
    'opencode-serve.sh'
    'opencode-serve.cmd'
)

function Get-OpenCodeLauncherFile {
    # The names of the launcher files, as a copy.
    return @($OpenCodeLauncherFiles)
}

function Get-OpenCodeLauncherState {
    # Where the launcher is, and whether a second one is lying around.
    #
    #   ScriptPath -- where the launcher MUST be
    #   ProfileDir -- the profile of the user, where it must NOT be any more
    #
    # The result:
    #   ScriptPath -- the path that was asked about
    #   Present    -- whether the launcher is there
    #   Stray      -- the names of the opencode-serve.* files in the profile
    #
    # A stray is not a failure of the machine, it is a leftover of the old
    # arrangement: two launchers mean two behaviours, and the owner has to
    # look at the file before it goes.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        [string]$ProfileDir = ''
    )

    $state = [pscustomobject]@{
        ScriptPath = $ScriptPath
        Present    = (Test-Path -LiteralPath $ScriptPath -PathType Leaf)
        Stray      = @()
    }

    if (-not $ProfileDir) { return $state }
    if (-not (Test-Path -LiteralPath $ProfileDir -PathType Container)) { return $state }

    $state.Stray = @(Get-ChildItem -LiteralPath $ProfileDir -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -like 'opencode-serve.*' } |
                     ForEach-Object { $_.Name } |
                     Sort-Object)
    return $state
}

function Install-OpenCodeLauncher {
    # Copies the launcher template into the target directory.
    #
    # The result:
    #   Written  -- the files that are in place now
    #   Missing  -- the templates that were not in the template directory
    #
    # Nothing is deleted, and a file that is already there is overwritten
    # with the template of the repository: the launcher is declared, not
    # hand-tuned per host.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateDir,
        [Parameter(Mandatory)]
        [string]$TargetDir
    )

    $result = [pscustomobject]@{
        TemplateDir = $TemplateDir
        TargetDir   = $TargetDir
        Written     = @()
        Missing     = @()
    }

    foreach ($name in (Get-OpenCodeLauncherFile)) {
        $source = Join-Path $TemplateDir $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            $result.Missing += $name
            continue
        }
        if (-not (Test-Path -LiteralPath $TargetDir -PathType Container)) {
            New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        }
        $target = Join-Path $TargetDir $name
        Copy-Item -LiteralPath $source -Destination $target -Force
        $result.Written += $target
    }
    return $result
}
