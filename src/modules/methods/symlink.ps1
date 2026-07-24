param(
    [ValidateSet("deploy", "clean")]
    [string]$action,
    [string]$from,
    [string]$to,
    $mappings = $null
)

function Remove-ItemLogged {
    param([string]$path)
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force
        Write-Host "    Removed $path" -ForegroundColor DarkYellow
    }
}

function Get-SymlinkTarget {
    param([string]$path)
    $item = Get-Item $path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        return $item.Target
    }
    return $null
}

function Set-Symlink {
    param([string]$source, [string]$target)
    $parent = Split-Path $target -Parent
    if (-not (Test-Path $parent)) {
        New-Item $parent -ItemType Directory -Force | Out-Null
    }
    $current = Get-SymlinkTarget $target
    if ($current -and $current -eq $source) {
        Write-Host "    Up-to-date: $target -> $source" -ForegroundColor DarkGray
        return
    }
    if (Test-Path $target) {
        Remove-Item $target -Recurse -Force
        Write-Host "    Removed $target" -ForegroundColor DarkYellow
    }
    New-Item -Path $target -ItemType SymbolicLink -Value $source -Force | Out-Null
    Write-Host "    Symlink created: $target -> $source" -ForegroundColor Green
}

switch ($action) {
    "deploy" {
        if ($mappings -and $mappings.Count -gt 0) {
            foreach ($m in $mappings) {
                $src = Join-Path $from $m.from
                $dst = Join-Path $to $m.to
                Set-Symlink $src $dst
            }
        } else {
            Set-Symlink $from $to
        }
    }
    "clean" {
        if ($mappings -and $mappings.Count -gt 0) {
            foreach ($m in $mappings) {
                $dst = Join-Path $to $m.to
                Remove-ItemLogged $dst
            }
        } else {
            Remove-ItemLogged $to
        }
    }
}
