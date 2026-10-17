# Manifest.ps1 -- Load, validate, and query plugin manifests.
#
# Manifests live in $root/manifests/<Name>.json and describe a plugin's full
# install/uninstall behavior: which junction targets, which copies, which
# registry files to import, which scripts to run before destructive ops.
#
# Schema (JSON):
# {
#   "Name":        "Waves",                     // optional; defaults to file basename
#   "Description": "Waves Complete",           // optional
#   "Links":       [ { "From": "...", "To": "...", "Kind": "Junction" } ],
#   "Copy":        [ { "From": "...", "To": "..." } ],
#   "Registry":    [ { "OnEnable": "...", "OnDisable": "..." } ],
#   "Process":     [ { "BeforeRevert": "..." } ]
# }
#
# Key naming: keys are PascalCase to match this module's field names. Lookups go
# through Get-Prop, which resolves case-insensitively, so camelCase also works.
#
# Path convention:
#   - "From" is relative to $pluginRoot unless it is already an absolute path.
#   - "To" is used verbatim (system paths). Absolute, or relative to $pluginRoot.
#   - JSON strings cannot contain $env:VAR references (they are literal), so
#     manifests use literal system paths.

# Get-Prop -- Case-insensitive property read that tolerates missing keys.
#
# PSCustomObject property access returns $null for missing keys in normal mode
# but throws under Set-StrictMode. Routing every read through here keeps the
# rest of this module free of edge cases.
function Get-Prop {
    param(
        $Object,
        [Parameter(Mandatory)] [string]$Name
    )
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals($key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $Object[$key]
            }
        }
        return $null
    }
    $prop = $Object.PSObject.Properties |
        Where-Object { [string]::Equals($_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if ($prop) { return $prop.Value }
    return $null
}

# Get-ManifestSection -- Read a manifest section as a real array.
#
# ConvertFrom-Json unwraps single-element JSON arrays into a bare scalar, so
# `"Links": [ { ... } ]` can surface as a PSCustomObject. Every caller needs an
# array, so normalize here: wrap non-null, non-array objects back into an array.
# Anything else (string, number) is returned as-is for the validator to reject.
function Get-ManifestSection {
    param(
        $Manifest,
        [Parameter(Mandatory)] [string]$Name
    )

    $value = Get-Prop $Manifest $Name
    if ($null -eq $value) { return $null }
    if ($value -is [System.Array]) { return $value }
    if ($value -is [PSCustomObject]) { return , @($value) }
    return $value
}

# Test-Manifest -- Validate a deserialized manifest against the schema.
#
# Returns $true when the manifest is structurally usable, $false otherwise.
# Every problem is reported via Write-Warning so a bad manifest is loud rather
# than silently skipped.
function Test-Manifest {
    [CmdletBinding()]
    param(
        $Manifest,
        [string]$Path = '<memory>'
    )

    $problems = @()

    if ($null -eq $Manifest) {
        Write-Warning "Manifest '$Path' is empty or null."
        return $false
    }

    if ($Manifest -is [System.Array]) {
        Write-Warning "Manifest '$Path' must be a JSON object at the top level, not an array."
        return $false
    }

    if ($Manifest -isnot [PSCustomObject]) {
        Write-Warning "Manifest '$Path' did not deserialize to an object (got $($Manifest.GetType().Name))."
        return $false
    }

    $name = Get-Prop $Manifest 'Name'
    if ($null -ne $name -and [string]::IsNullOrWhiteSpace($name)) {
        $problems += 'Name is present but empty'
    }

    # Required keys per section.
    $requiredKeys = @{
        Links    = @('From', 'To')
        Copy     = @('From', 'To')
    }

    foreach ($section in @('Links', 'Copy', 'Registry', 'Process')) {
        $items = Get-ManifestSection -Manifest $Manifest -Name $section
        if ($null -eq $items) { continue }

        if ($items -isnot [System.Array]) {
            $problems += "$section must be a JSON array of objects"
            continue
        }

        foreach ($item in $items) {
            if ($null -eq $item) { continue }

            if ($section -eq 'Registry') {
                $hasEnable  = [bool](Get-Prop $item 'OnEnable')
                $hasDisable = [bool](Get-Prop $item 'OnDisable')
                if (-not ($hasEnable -or $hasDisable)) {
                    $problems += 'Registry entry needs "OnEnable" and/or "OnDisable"'
                }
                continue
            }

            if ($section -eq 'Process') {
                if (-not (Get-Prop $item 'BeforeRevert')) {
                    $problems += 'Process entry needs "BeforeRevert"'
                }
                continue
            }

            foreach ($key in $requiredKeys[$section]) {
                if (-not (Get-Prop $item $key)) {
                    $problems += "$section entry missing `"$key`""
                }
            }
        }
    }

    foreach ($problem in $problems) {
        Write-Warning "Manifest '$Path': $problem"
    }

    return ($problems.Count -eq 0)
}

# Get-PluginManifest -- Load and validate manifests/<Name>.json.
#
# Returns a normalized manifest (with Links/Copy/Registry/Process keys always
# present, $null when the section is absent) or $null when the file is missing,
# unparseable, or fails schema validation.
function Get-PluginManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$ManifestDir
    )

    $path = Join-Path $ManifestDir "$Name.json"
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    $manifest = $null
    try {
        $raw = Get-Content -Raw -LiteralPath $path -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Warning "Manifest '$path' is empty."
            return $null
        }
        $manifest = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "Failed to parse manifest '$path': $($_.Exception.Message)"
        return $null
    }

    if (-not (Test-Manifest -Manifest $manifest -Path $path)) {
        return $null
    }

    # Normalize: guarantee all four section keys exist so callers never touch
    # a missing property.
    foreach ($key in @('Links', 'Copy', 'Registry', 'Process')) {
        if ($null -eq (Get-Prop $manifest $key)) {
            $manifest | Add-Member -MemberType NoteProperty -Name $key -Value $null -Force
        }
    }

    $manifest
}

# Expand-PathTokens -- Expand %VAR% into environment variables.
#
# Uses Windows-native %VAR% syntax rather than $env:VAR because JSON strings are
# literal and $env: cannot be evaluated by ConvertFrom-Json, while %VAR% matches
# the syntax the vendor .bat installers already used. Handles names with
# parentheses such as %ProgramFiles(x86)%.
#
# An unresolved token is left verbatim rather than blanked, so a typo shows up as
# a missing file at run time instead of silently becoming a relative path.
function Expand-PathTokens {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if (-not $Path.Contains('%')) { return $Path }

    return [regex]::Replace($Path, '%([^%]+)%', {
        param($match)
        $name = $match.Groups[1].Value
        $value = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrEmpty($value)) { return $match.Value }
        return $value
    })
}

# Resolve-ManifestPath -- Resolve a manifest path to an absolute one.
#
# Order: expand %VAR% tokens, then use the path as-is if rooted, otherwise join
# against the plugin's own folder.
#
# $BaseDir must be the plugin's own folder (e.g. S:\Plugins\Waves), NOT the
# global plugin root. Manifest paths are written relative to the plugin folder
# (e.g. "R2R\1.reg" -> S:\Plugins\Waves\R2R\1.reg), so passing the global root
# here would silently produce S:\Plugins\R2R\1.reg and miss the file.
function Resolve-ManifestPath {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$BaseDir
    )

    $expanded = Expand-PathTokens -Path $Path
    $expanded = ConvertTo-SandboxPath -Path $expanded
    if ([System.IO.Path]::IsPathRooted($expanded)) { return $expanded }
    Join-Path $BaseDir $expanded
}

# Get-ManifestLinks -- Extract link mappings from manifest, with paths resolved.
function Get-ManifestLinks {
    [CmdletBinding()]
    param(
        $Manifest,
        [Parameter(Mandatory)] [string]$BaseDir
    )

    $items = Get-ManifestSection -Manifest $Manifest -Name 'Links'
    if ($null -eq $items) { return @() }

    $links = @()
    foreach ($l in $items) {
        if ($null -eq $l) { continue }
        $from = Get-Prop $l 'From'
        $to   = Get-Prop $l 'To'
        if (-not $from -or -not $to) { continue }
        $links += [PSCustomObject]@{
            From = Resolve-ManifestPath -Path $from -BaseDir $BaseDir
            To   = Resolve-ManifestPath -Path $to   -BaseDir $BaseDir
            Kind = if (Get-Prop $l 'Kind') { Get-Prop $l 'Kind' } else { 'Junction' }
        }
    }
    , $links
}

# Get-ManifestCopySteps -- Return Copy steps with absolute paths.
function Get-ManifestCopySteps {
    [CmdletBinding()]
    param(
        $Manifest,
        [Parameter(Mandatory)] [string]$BaseDir
    )

    $items = Get-ManifestSection -Manifest $Manifest -Name 'Copy'
    if ($null -eq $items) { return @() }

    $steps = @()
    foreach ($c in $items) {
        if ($null -eq $c) { continue }
        $from = Get-Prop $c 'From'
        $to   = Get-Prop $c 'To'
        if (-not $from -or -not $to) { continue }
        $steps += [PSCustomObject]@{
            From = Resolve-ManifestPath -Path $from -BaseDir $BaseDir
            To   = Resolve-ManifestPath -Path $to   -BaseDir $BaseDir
        }
    }
    , $steps
}

# Get-ManifestRegistrySteps -- Return registry steps for 'enable' or 'disable'.
function Get-ManifestRegistrySteps {
    [CmdletBinding()]
    param(
        $Manifest,
        [Parameter(Mandatory)] [ValidateSet('enable', 'disable')] [string]$Action,
        [Parameter(Mandatory)] [string]$BaseDir
    )

    $items = Get-ManifestSection -Manifest $Manifest -Name 'Registry'
    if ($null -eq $items) { return @() }

    $field = if ($Action -eq 'enable') { 'OnEnable' } else { 'OnDisable' }

    $steps = @()
    foreach ($r in $items) {
        if ($null -eq $r) { continue }
        $rel = Get-Prop $r $field
        if (-not $rel) { continue }
        $steps += [PSCustomObject]@{
            RegFile = Resolve-ManifestPath -Path $rel -BaseDir $BaseDir
            Action  = $Action
        }
    }
    , $steps
}

# Get-ManifestProcessSteps -- Return process steps for a trigger.
function Get-ManifestProcessSteps {
    [CmdletBinding()]
    param(
        $Manifest,
        [Parameter(Mandatory)] [ValidateSet('beforeRevert')] [string]$Trigger,
        [Parameter(Mandatory)] [string]$BaseDir
    )

    $items = Get-ManifestSection -Manifest $Manifest -Name 'Process'
    if ($null -eq $items) { return @() }

    $field = if ($Trigger -eq 'beforeRevert') { 'BeforeRevert' } else { $null }
    if (-not $field) { return @() }

    $steps = @()
    foreach ($p in $items) {
        if ($null -eq $p) { continue }
        $rel = Get-Prop $p $field
        if (-not $rel) { continue }
        $steps += [PSCustomObject]@{
            Script  = Resolve-ManifestPath -Path $rel -BaseDir $BaseDir
            Trigger = $Trigger
        }
    }
    , $steps
}