Describe "build-mappings.ps1" {
    BeforeAll {
        $script:Builder = Join-Path $PSScriptRoot "../scripts/build-mappings.ps1"
        $script:TestDir = Join-Path $env:TEMP "winos-build-mappings-test"
        if (Test-Path $script:TestDir) {
            Remove-Item $script:TestDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:TestDir "sub") -Force | Out-Null
        "a" | Out-File -FilePath (Join-Path $script:TestDir "top1.txt") -Encoding utf8
        "b" | Out-File -FilePath (Join-Path $script:TestDir "top2.txt") -Encoding utf8
        "c" | Out-File -FilePath (Join-Path $script:TestDir "sub/nested.txt") -Encoding utf8
    }

    AfterAll {
        if (Test-Path $script:TestDir) {
            Remove-Item $script:TestDir -Recurse -Force
        }
    }

    It "exists" {
        Test-Path $script:Builder | Should -Be $true
    }

    It "is valid PowerShell" {
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:Builder, [ref]$tokens, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "exits non-zero on missing source" {
        $proc = Start-Process -FilePath "pwsh" -ArgumentList @("-NoProfile", "-File", $script:Builder, "-Path", "/nonexistent/path/xyz") -Wait -PassThru -NoNewWindow
        $proc.ExitCode | Should -Not -Be 0
    }

    It "produces top-level files only by default" {
        $json = pwsh -File $script:Builder -Path $script:TestDir -AsJson
        $lines = $json | ConvertFrom-Json
        $lines.Count | Should -Be 2
        ($lines | ForEach-Object { $_.from }) | Should -Contain "top1.txt"
        ($lines | ForEach-Object { $_.from }) | Should -Contain "top2.txt"
        ($lines | ForEach-Object { $_.from }) | Should -Not -Contain "sub/nested.txt"
    }

    It "includes subdirectories with -Recurse" {
        $json = pwsh -File $script:Builder -Path $script:TestDir -Recurse -AsJson
        $lines = $json | ConvertFrom-Json
        $lines.Count | Should -Be 3
        ($lines | ForEach-Object { $_.from }) | Should -Contain "sub/nested.txt"
    }

    It "produces 1:1 mirror mappings (from == to)" {
        $json = pwsh -File $script:Builder -Path $script:TestDir -Recurse -AsJson
        $lines = $json | ConvertFrom-Json
        foreach ($line in $lines) {
            $line.from | Should -Be $line.to
        }
    }

    It "uses forward slashes for relative paths" {
        $json = pwsh -File $script:Builder -Path $script:TestDir -Recurse -AsJson
        $lines = $json | ConvertFrom-Json
        $nested = $lines | Where-Object { $_.from -like "sub/*" }
        $nested | Should -Not -BeNullOrEmpty
        $nested.from | Should -BeLike "sub/*"
        $nested.from | Should -Not -BeLike "*\*"
    }
}
