# Discovery.ps1 -- Auto-discover plugin mappings from S:\Plugins folder structure
# and adopt existing on-system junctions into state/plugin-deployment.json.
#
# Two layers of heuristics:
#   1. Top-level VST2/VST3/vst directories (simple case, e.g. FabFilter, BOBOC).
#   2. Top-level C\ subtree mirroring system paths (complex case, e.g. Waves, Neural DSP).
#
# These cover ~30+ plugins in the user's library without requiring a per-plugin
# manifest. Plugin.psd1 (Phase 3) lets a plugin override or extend these defaults.

# Get-PluginFolders -- Enumerate top-level plugin folders under $pluginRoot.
function Get-PluginFolders {
    param([Parameter(Mandatory)] [string]$PluginRoot)

    if (-not (Test-Path -LiteralPath $PluginRoot -PathType Container)) {
        return @()
    }

    # The sandbox source tree lives inside the plugin library (S:\Plugins\Test),
    # so it must never be enumerated as a plugin in its own right -- otherwise it
    # shows up as a plugin named "Test" and gets its own mappings. Skipped whether
    # or not the sandbox is currently enabled, since the scratch tree is not a
    # plugin regardless of which mode a later run uses.
    $sandboxSource = $null
    if (Get-Command Test-SandboxActive -ErrorAction SilentlyContinue) {
        if (Test-SandboxActive) {
            $sandboxSource = [System.IO.Path]::GetFullPath($script:PluginSandbox.SourceRoot).TrimEnd('\', '/')
        }
    }
    if (-not $sandboxSource) {
        $defaultScratch = Join-Path $PluginRoot 'Test'
        if (Test-Path -LiteralPath $defaultScratch -PathType Container) {
            $sandboxSource = [System.IO.Path]::GetFullPath($defaultScratch).TrimEnd('\', '/')
        }
    }

    Get-ChildItem -LiteralPath $PluginRoot -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -notlike '.*' -and
            $_.Name -ne 'desktop.ini' -and
            -not ($sandboxSource -and
                  [System.IO.Path]::GetFullPath($_.FullName).TrimEnd('\', '/') -eq $sandboxSource)
        }
}

# Resolve-CPath is no longer used by discovery -- see the note in Discover-Plugin
# for why the C:\ mirror cannot be inferred. It is kept because the generated
# manifests and the audit script both reason in those terms, and removing it
# would only move the vocabulary elsewhere.

# Discover-Plugin -- Inspect one plugin folder, return its discovered mappings.
#
# Output:
#   [PSCustomObject]@{
#       Name      = "FabFilter - Total Bundle"
#       SourceDir = "S:\Plugins\FabFilter - Total Bundle"
#       Mappings  = @( [PSCustomObject]@{ From = "..."; To = "..."; Kind = "Junction" }, ... )
#   }
function Discover-Plugin {
    param([Parameter(Mandatory)] [string]$PluginDir)
    
    $name = Split-Path -Leaf $PluginDir
    $mappings = @()
    
    # Heuristic A: top-level VST2/VST3/vst directories.
    foreach ($vstDir in @('VST2', 'VST3', 'vst')) {
        $vstPath = Join-Path $PluginDir $vstDir
        if (-not (Test-Path -LiteralPath $vstPath -PathType Container)) { continue }
        
        $subdirs = Get-ChildItem -LiteralPath $vstPath -Directory -Force -ErrorAction SilentlyContinue
        foreach ($sub in $subdirs) {
            # Build the real system path first, then redirect it if sandboxed.
            # Skipping the redirect here would probe the live Program Files during a
            # sandbox run and could rewrite real junctions.
            if ($vstDir -eq 'VST3') {
                $target = Join-Path $env:COMMONPROGRAMFILES ("VST3\" + $sub.Name)
            } else {
                $target = Join-Path $env:PROGRAMFILES ("VSTPlugins\" + $sub.Name)
            }
            $mappings += [PSCustomObject]@{
                From = ConvertTo-SandboxPath -Path $sub.FullName
                To   = ConvertTo-SandboxPath -Path $target
                Kind = 'Junction'
            }
        }
    }
    
    # Heuristic B (C:\ subtree mirroring system paths) was removed.
    #
    # It tried to infer link targets by walking the C:\ mirror and mapping every
    # leaf directory onto its system path. Measured against the live system:
    #
    #     plugin            heuristic   actually correct
    #     Arturia FX Coll.      1603              3
    #     Vengeance Avenger     1016              2
    #     Toontrack              362              2
    #     Acon Digital           170              2
    #     Soundtoys              113              0
    #
    # No depth threshold separates them: correct mappings all sit at depth 2,
    # but so do 15 incorrect ones, while wrong ones also appear at depth 1 and 10.
    # The subtree holds both install locations and vendor content trees, and
    # nothing in the layout distinguishes them.
    #
    # Plugins with a C:\ mirror therefore need an explicit manifest. The same
    # applies to layouts where the VST folder is itself the payload rather than a
    # container, e.g. Synth1's vst\ or Dear Reality's VST3\, which hold the DLL
    # directly and yield no subdirectories to walk.
    #
    # Heuristic A above stays: a VST2/VST3/vst folder containing one directory
    # per plugin is unambiguous.
    
    [PSCustomObject]@{
        Name      = $name
        SourceDir = $PluginDir
        Mappings  = $mappings
    }
}

# Discover-AllPlugins -- Convenience wrapper: scan $pluginRoot and return all discovered plugins.
function Discover-AllPlugins {
    param([Parameter(Mandatory)] [string]$PluginRoot)
    
    Get-PluginFolders -PluginRoot $PluginRoot | ForEach-Object {
        Discover-Plugin -PluginDir $_.FullName
    }
}

# Invoke-Adopt -- Scan standard system paths for existing junctions pointing
# under $pluginRoot, group them by plugin, write a fresh state/plugin-deployment.json.
#
# This is the migration entry-point: if you had old .bat scripts creating symlinks
# on the system, adopt captures them so you can manage them through the module.
#
# Only ACTIVE plugins end up in state.json. Inactive plugin folders in $pluginRoot
# are NOT listed (they remain ignored by default per the state.json spec). Add them
# manually or via a future `discover` verb.
function Invoke-Adopt {
    param(
        [Parameter(Mandatory)] [string]$PluginRoot,
        [Parameter(Mandatory)] [string]$StateFile
    )
    
    $sandboxRoots = Get-SandboxScanRoots

    if ($null -ne $sandboxRoots) {
        $roots = @($sandboxRoots | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
    } else {
        # Standard system roots where plugin junctions live.
        $roots = @(
            (Join-Path $env:PROGRAMFILES 'VSTPlugins'),
            (Join-Path $env:COMMONPROGRAMFILES 'VST3'),
            (Join-Path $env:COMMONPROGRAMFILES 'Avid\Audio\Plug-Ins'),
            (Join-Path $env:PROGRAMFILES 'Steinberg\VSTPlugins')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    }
    
    $normalizedRoot = $PluginRoot.TrimEnd('\', '/')
    $byPlugin = [ordered]@{}
    
    foreach ($root in $roots) {
        # Recursive: a plugin may nest its junction a level down, e.g. iZotope
        # lives at <root>\VST3\iZotope\Ozone 11 rather than directly under VST3.
        Get-ChildItem -LiteralPath $root -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint
        } | ForEach-Object {
            $link = $_
            $target = $link.Target
            if ($null -eq $target) { return }
            
            $normalizedTarget = $target.TrimEnd('\', '/')
            if (-not $normalizedTarget.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return }
            
            # First segment under $pluginRoot is the plugin name.
            $rel = $normalizedTarget.Substring($normalizedRoot.Length).TrimStart('\', '/')
            $name = $rel.Split('\')[0]
            
            if (-not $byPlugin.Contains($name)) {
                $byPlugin[$name] = [PSCustomObject]@{
                    Name     = $name
                    Link     = $true
                    Ignore   = $false
                    Mappings = @()
                }
            }
            $byPlugin[$name].Mappings += [PSCustomObject]@{
                From = $target
                To   = $link.FullName
                Kind = 'Junction'
            }
        }
    }
    
    $plugins = @($byPlugin.Values)
    
    $state = [PSCustomObject]@{
        version      = $stateVersion
        tool_version = $toolVersion
        plugins      = $plugins
    }
    
    Write-PluginDeploymentState -Path $StateFile -Data $state
    $state
}
