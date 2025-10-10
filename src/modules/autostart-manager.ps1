param(
    [string]$action = "update" # update, remove
)

# $autostartDir = "C:\Path\To\Autostart"
$taskPrefix = "winos_"

function Get-ManagedTasks {
    Get-ScheduledTask | Where-Object {$_.TaskName -like "$taskPrefix*"}
}
function Update-Tasks($shortcut) {
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($shortcut.FullName)
    $taskName = "$taskPrefix$($shortcut.BaseName)"

    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    # Добавляем аргументы из ярлыка
    $actionObj = New-ScheduledTaskAction -Execute $sc.TargetPath -Argument $sc.Arguments
    if ($sc.WorkingDirectory) { $actionObj.WorkingDirectory = $sc.WorkingDirectory }
    $trigger = New-ScheduledTaskTrigger -AtLogOn

    if ($existingTask) {
        Set-ScheduledTask -TaskName $taskName -Action $actionObj -Trigger $trigger
    } else {
        Register-ScheduledTask -TaskName $taskName -Action $actionObj -Trigger $trigger -User $env:USERNAME -RunLevel Highest -Force
    }
}


function Remove-AllTasks($tasks) {
    foreach ($t in $tasks) {
        Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
    }
}

switch ($action) {
    "update" {
        if (-Not (Test-Path $autostartDir)) {
            Write-Error "Папка автозапуска не найдена: $autostartDir"
            break
        }

        # Получаем все ярлыки из папки
        $shortcuts = Get-ChildItem -Path $autostartDir -Filter *.lnk

        # Создаем/обновляем задачи по ярлыкам
        foreach ($sc in $shortcuts) {
            Update-Tasks $sc
        }

        # Удаляем задачи, которых нет в папке
        $existingTasks = Get-ManagedTasks
        foreach ($t in $existingTasks) {
            $nameWithoutPrefix = $t.TaskName.Substring($taskPrefix.Length)
            if (-Not ($shortcuts.BaseName -contains $nameWithoutPrefix)) {
                Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
            }
        }
    }
    "remove" {
        Remove-AllTasks (Get-ManagedTasks)
    }
    default {
        Write-Error "Неизвестное действие: $action. Используйте 'update' или 'remove'."
    }
}
