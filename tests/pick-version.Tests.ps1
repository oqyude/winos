BeforeAll {
    # scripts/pick-version.py decides which version a manifest is updated to.
    # It is the piece the auto-update workflow depends on, and a wrong answer
    # silently keeps a stale manifest (or skips it entirely), so the rules
    # are pinned here.
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    $script:PickScript = Join-Path $script:RepoRoot "scripts/pick-version.py"
    $script:Python = @('python3', 'python') |
        Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } |
        Select-Object -First 1

    # Defined here, not in the Describe body: Pester runs discovery and the
    # test bodies in different phases, and a function created during discovery
    # is not in scope when the test runs.
    function Invoke-Pick {
        param(
            [Parameter(Mandatory)][AllowEmptyString()][string]$Regex,
            [Parameter(Mandatory)][string]$Body,
            [switch]$Text
        )
        $arguments = @()
        if ($Text) { $arguments += '--text' }
        $arguments += $Regex
        $output = $Body | & $script:Python $script:PickScript @arguments
        return ($output | Out-String).Trim()
    }
}

Describe "pick-version.py" {
    BeforeAll {
        if (-not $script:Python) {
            Set-ItResult -Skipped -Because 'python is not installed'
        }
    }

    It 'picks the versioned release when a rolling "latest" release is on top' {
        # incy-platforms keeps a "latest" release above the versioned ones,
        # which is what made the single-release endpoint useless for it.
        $body = @'
[{"tag_name":"latest","draft":false,"prerelease":false},
 {"tag_name":"desktop-v3.9.0","draft":false,"prerelease":false}]
'@
        Invoke-Pick -Regex 'desktop-v([\d.]+)' -Body $body | Should -Be '3.9.0'
    }

    It 'uses the capture group as the version' {
        $body = '[{"tag_name":"v1.0.0","draft":false,"prerelease":false}]'
        Invoke-Pick -Regex 'v([\d.]+)' -Body $body | Should -Be '1.0.0'
    }

    It 'uses the whole match when the regex has no capture group' {
        # The whole match is the version, and a leading v is stripped like it
        # is on a plain tag.
        $body = '[{"tag_name":"v1.0.0","draft":false,"prerelease":false}]'
        Invoke-Pick -Regex 'v[\d.]+' -Body $body | Should -Be '1.0.0'
    }

    It 'strips the leading v from the tag when there is no regex' {
        $body = '[{"tag_name":"v1.8.0","draft":false,"prerelease":false}]'
        Invoke-Pick -Regex '' -Body $body | Should -Be '1.8.0'
    }

    It 'skips a rolling "latest" tag when there is no regex' {
        $body = '[{"tag_name":"latest","draft":false,"prerelease":false}]'
        Invoke-Pick -Regex '' -Body $body | Should -Be ''
    }

    It 'ignores drafts' {
        $body = @'
[{"tag_name":"v9.9.9","draft":true,"prerelease":false},
 {"tag_name":"v1.0.0","draft":false,"prerelease":false}]
'@
        Invoke-Pick -Regex '' -Body $body | Should -Be '1.0.0'
    }

    It 'prefers a stable release over a prerelease' {
        $body = @'
[{"tag_name":"v2.0.0-beta.1","draft":false,"prerelease":true},
 {"tag_name":"v1.0.0","draft":false,"prerelease":false}]
'@
        Invoke-Pick -Regex '' -Body $body | Should -Be '1.0.0'
    }

    It 'uses the prerelease when the repository has no stable release' {
        $body = '[{"tag_name":"v4.0.0-beta.12","draft":false,"prerelease":true}]'
        Invoke-Pick -Regex 'v([\d.]+-beta\.\d+)' -Body $body | Should -Be '4.0.0-beta.12'
    }

    It 'matches the regex against the body in --text mode' {
        $body = '[{"name":"Release 1.4.2","tag_name":"1.4.2"}]'
        Invoke-Pick -Regex '"tag_name":"([\d.]+)"' -Body $body -Text | Should -Be '1.4.2'
    }

    It 'takes the highest version among several matches in --text mode' {
        # A list of refs follows the git ref listing, not the version order:
        # v0.1.9 comes before v0.1.10 there, and picking the first match
        # would downgrade the manifest.
        $body = '[{"name":"v0.1.9"},{"name":"v0.1.2"},{"name":"v0.1.10"}]'
        Invoke-Pick -Regex '"name":\s*"v?([^"]+)"' -Body $body -Text | Should -Be '0.1.10'
    }

    It 'ignores matches that are not versions in --text mode' {
        $body = '[{"name":"fork"},{"name":"v1.2.3"}]'
        Invoke-Pick -Regex '"name":\s*"v?([^"]+)"' -Body $body -Text | Should -Be '1.2.3'
    }

    It 'yields nothing in --text mode without a regex' {
        $body = '[{"tag_name":"1.4.2"}]'
        Invoke-Pick -Regex '' -Body $body -Text | Should -Be ''
    }
}
