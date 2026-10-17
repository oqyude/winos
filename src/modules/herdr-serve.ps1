[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("setup", "remove", "status", "start", "stop")]
    [string]$action
)

# Self-bootstrap: if vars.ps1 hasn't been sourced (run directly), source it.
if (-not $Storage) {
    . (Join-Path $PSScriptRoot "..\init.ps1")
}

# herdr is a headless server (no HTTP port). Its API lives on a local socket at
# %APPDATA%\Roaming\herdr\herdr.sock; clients connect to it from terminals and
# IDE plugins. The scheduled task launches `herdr server` at logon so the
# persistent session is already running when the user opens a terminal.
$serviceName = "HerdrServe"
$configDir   = Join-Path $data "herdr-serve"
$configFile  = Join-Path $configDir "config.json"
$runnerScript = Join-Path $PSScriptRoot "herdr-serve\runner.ps1"

switch ($action) {
    "setup" {
        if (-not $PSCmdlet.ShouldProcess($serviceName, "Install herdr-serve scheduled task")) {
            return
        }

        # 1. Verify herdr is in PATH
        try {
            $herdrPath = (Get-Command "herdr" -ErrorAction Stop).Source
        }
        catch {
            Write-Host "herdr not found in PATH. Install it first." -ForegroundColor Red
            exit 1
        }

        # 2. Create configDir
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        # 3. Create/update config.json. allowUnelevatedClients mirrors what the
        #    operator set with `herdr server --allow-unelevated-clients` on the
        #    command line so a future setup rerun reproduces the same surface.
        $config = @{
            herdr                  = $herdrPath
            allowUnelevatedClients = $true
        }
        $config | ConvertTo-Json | Set-Content -Path $configFile -Encoding utf8

        # 4. Register Scheduled Task.
        #    Limited user: same shape as opencode-serve. -AllowStartIfOnBatteries +
        #    RestartCount 5 keep the server up across brief sleep/wake cycles
        #    without forcing the user to relogin.
        $actionTask = New-ScheduledTaskAction -Execute "powershell.exe" -Argument @"
-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$runnerScript"
"@

        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit 0

        Register-ScheduledTask -TaskName $serviceName -Action $actionTask `
            -Trigger $trigger -Settings $settings -User $env:USERNAME `
            -RunLevel Limited -Force | Out-Null

        Write-Host "Herdr Serve service installed. Starting..." -ForegroundColor Green
        Start-ScheduledTask -TaskName $serviceName | Out-Null
    }

    "remove" {
        if (-not $PSCmdlet.ShouldProcess($serviceName, "Remove herdr-serve scheduled task")) {
            return
        }

        Stop-ScheduledTask -TaskName $serviceName -ErrorAction SilentlyContinue | Out-Null
        Unregister-ScheduledTask -TaskName $serviceName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        if (Test-Path $configDir) {
            Remove-Item -Path $configDir -Recurse -Force | Out-Null
        }
        Write-Host "Herdr Serve service removed." -ForegroundColor Yellow
    }

    "status" {
        $task = Get-ScheduledTask -TaskName $serviceName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host "Herdr Serve: NOT INSTALLED" -ForegroundColor Red
            exit 1
        }

        $info   = Get-ScheduledTaskInfo -TaskName $serviceName -ErrorAction SilentlyContinue
        $status = $task.State
        $color  = switch ($status) {
            "Ready"    { "Green" }
            "Running"  { "Green" }
            "Disabled" { "Red" }
            default    { "Yellow" }
        }

        Write-Host "Herdr Serve:" -ForegroundColor Cyan
        Write-Host "  State:       " -NoNewline; Write-Host $status -ForegroundColor $color
        Write-Host "  Last Run:    $($info.LastRunTime)" -ForegroundColor DarkGray
        Write-Host "  Last Result: $($info.LastTaskResult)" -ForegroundColor DarkGray
        Write-Host "  Next Run:    $($info.NextRunTime)" -ForegroundColor DarkGray

        $proc = Get-Process -Name "herdr" -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "  Process:     " -NoNewline; Write-Host "Running (PID: $($proc.Id))" -ForegroundColor Green
        }
        else {
            Write-Host "  Process:     " -NoNewline; Write-Host "Not running" -ForegroundColor Red
        }

        if (Test-Path $configFile) {
            $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
            $unelevated = if ($cfg.allowUnelevatedClients) { "true" } else { "false" }
            Write-Host "  Config:      herdr=$($cfg.herdr), unelevated=$unelevated" -ForegroundColor DarkGray
        }
    }

    "start" {
        if ($PSCmdlet.ShouldProcess($serviceName, "Start herdr-serve task")) {
            Start-ScheduledTask -TaskName $serviceName -ErrorAction Stop | Out-Null
            Write-Host "Herdr Serve started." -ForegroundColor Green
        }
    }

    "stop" {
        if ($PSCmdlet.ShouldProcess($serviceName, "Stop herdr-serve task")) {
            Stop-ScheduledTask -TaskName $serviceName -ErrorAction Stop | Out-Null
            Write-Host "Herdr Serve stopped." -ForegroundColor Yellow
        }
    }
}
