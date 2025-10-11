param(
    [string]$action = "update"
)

$taskPrefix = "winos_"

function Get-ManagedTasks {
    Get-ScheduledTask | Where-Object { $_.TaskName -like "$taskPrefix*" }
}

function Update-Tasks($shortcut) {
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($shortcut.FullName)
    $taskName = "$taskPrefix$($shortcut.BaseName)"

    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    $actionObj = New-ScheduledTaskAction -Execute $sc.TargetPath -Argument $sc.Arguments
    if ($sc.WorkingDirectory) { $actionObj.WorkingDirectory = $sc.WorkingDirectory }
    $trigger = New-ScheduledTaskTrigger -AtLogOn

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    if ($existingTask) {
        Set-ScheduledTask -TaskName $taskName -Action $actionObj -Trigger $trigger -Settings $settings | Out-Null
        Write-Host "[UPDATE] Task '$taskName' updated. Target: $($sc.TargetPath) Arguments: $($sc.Arguments)" -ForegroundColor Blue
    } else {
        Register-ScheduledTask -TaskName $taskName -Action $actionObj -Trigger $trigger -Settings $settings -User $env:USERNAME -RunLevel Highest -Force | Out-Null
        Write-Host "[CREATE] Task '$taskName' created. Target: $($sc.TargetPath) Arguments: $($sc.Arguments)" -ForegroundColor Blue
    }
}

function Remove-AllTasks($tasks) {
    foreach ($t in $tasks) {
        Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
        Write-Host "[REMOVE] Task '$($t.TaskName)' removed." -ForegroundColor Red
    }
}

switch ($action) {
    "update" {
        if (-not (Test-Path $autostartDir)) {
            Write-Error "Autostart folder not found: $autostartDir"
            break
        }

        $shortcuts = Get-ChildItem -Path $autostartDir -Filter *.lnk

        foreach ($sc in $shortcuts) {
            Update-Tasks $sc
        }

        $existingTasks = Get-ManagedTasks
        foreach ($t in $existingTasks) {
            $nameWithoutPrefix = $t.TaskName.Substring($taskPrefix.Length)
            if (-not ($shortcuts.BaseName -contains $nameWithoutPrefix)) {
                Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
                Write-Host "[REMOVE] Task '$($t.TaskName)' removed because shortcut no longer exists." -ForegroundColor DarkYellow
            }
        }
    }
    "remove" {
        Remove-AllTasks (Get-ManagedTasks)
    }
    default {
        Write-Error "Unknown action: $action. Use 'update' or 'remove'."
    }
}
