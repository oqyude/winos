[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("setup", "remove", "status", "start", "stop")]
    [string]$action
)

# Self-bootstrap: if vars.ps1 hasn't been sourced (run directly), source it.
if (-not $Storage) {
    . (Join-Path $PSScriptRoot "..\init.ps1")
}

$serviceName = "OpenCodeServe"
$configDir = Join-Path $data "opencode-serve"
$configFile = Join-Path $configDir "config.json"
$envFile = Join-Path $configDir ".env"
$runnerScript = Join-Path $PSScriptRoot "opencode-serve\runner.ps1"

switch ($action) {
    "setup" {
        # 1. Verify opencode is in PATH
        try {
            $opencodePath = (Get-Command "opencode" -ErrorAction Stop).Source
        }
        catch {
            Write-Host "opencode not found in PATH. Install it first." -ForegroundColor Red
            exit 1
        }

        # 2. Create configDir
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        # 3. Create/update config.json
        $config = @{
            hostname = "0.0.0.0"
            port     = 4096
            username = "opencode"
            opencode = $opencodePath
        }
        $config | ConvertTo-Json | Set-Content -Path $configFile -Encoding utf8

        # 4. Prompt for password if no .env and no env var
        if (-not (Test-Path $envFile) -and -not $env:OPENCODE_SERVER_PASSWORD) {
            $password = Read-Host "Enter OPENCODE_SERVER_PASSWORD (leave empty to skip)"
            if ($password) {
                "OPENCODE_SERVER_PASSWORD=$password" | Set-Content -Path $envFile -Encoding utf8
                # Protect file: current user read-only, no inheritance
                icacls $envFile /inheritance:r /grant "$env:USERNAME:R" | Out-Null
            }
        }

        # 5. Register Scheduled Task
        $action_task = New-ScheduledTaskAction -Execute "powershell.exe" -Argument @"
-NoProfile -ExecutionPolicy Bypass -File "$runnerScript"
"@

        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit 0

        Register-ScheduledTask -TaskName $serviceName -Action $action_task `
            -Trigger $trigger -Settings $settings -User $env:USERNAME `
            -RunLevel Limited -Force | Out-Null

        Write-Host "OpenCode Serve service installed. Starting..." -ForegroundColor Green
        Start-ScheduledTask -TaskName $serviceName | Out-Null
    }

    "remove" {
        Stop-ScheduledTask -TaskName $serviceName -ErrorAction SilentlyContinue | Out-Null
        Unregister-ScheduledTask -TaskName $serviceName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        if (Test-Path $configDir) {
            Remove-Item -Path $configDir -Recurse -Force | Out-Null
        }
        Write-Host "OpenCode Serve service removed." -ForegroundColor Yellow
    }

    "status" {
        $task = Get-ScheduledTask -TaskName $serviceName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host "OpenCode Serve: NOT INSTALLED" -ForegroundColor Red
            exit 1
        }

        $info = Get-ScheduledTaskInfo -TaskName $serviceName -ErrorAction SilentlyContinue
        $status = $task.State
        $color = switch ($status) {
            "Ready"    { "Green" }
            "Running"  { "Green" }
            "Disabled" { "Red" }
            default    { "Yellow" }
        }

        Write-Host "OpenCode Serve:" -ForegroundColor Cyan
        Write-Host "  State:       " -NoNewline; Write-Host $status -ForegroundColor $color
        Write-Host "  Last Run:    $($info.LastRunTime)" -ForegroundColor DarkGray
        Write-Host "  Last Result: $($info.LastTaskResult)" -ForegroundColor DarkGray
        Write-Host "  Next Run:    $($info.NextRunTime)" -ForegroundColor DarkGray

        # Check if opencode serve process is running
        $proc = Get-Process -Name "opencode" -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -match "serve"
        }
        if ($proc) {
            Write-Host "  Process:     " -NoNewline; Write-Host "Running (PID: $($proc.Id))" -ForegroundColor Green
        }
        else {
            Write-Host "  Process:     " -NoNewline; Write-Host "Not running" -ForegroundColor Red
        }

        if (Test-Path $configFile) {
            $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
            Write-Host "  Config:      http://$($cfg.hostname):$($cfg.port) (user: $($cfg.username))" -ForegroundColor DarkGray
        }
    }

    "start" {
        Start-ScheduledTask -TaskName $serviceName -ErrorAction Stop | Out-Null
        Write-Host "OpenCode Serve started." -ForegroundColor Green
    }

    "stop" {
        Stop-ScheduledTask -TaskName $serviceName -ErrorAction Stop | Out-Null
        Write-Host "OpenCode Serve stopped." -ForegroundColor Yellow
    }
}
