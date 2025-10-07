param(
    [string]$action = "reconnect"  # connect | disconnect | reconnect
)

Write-Host "Apps Manager запущен с действием: $action"

# CSV-файл с приложениями
$config = $appsAll

# Импорт CSV
$csv = Import-Csv -Path $config

foreach ($app in $csv) {
    # Пропускаем отключённые
    if ($app.Enabled -ne "1") { continue }

    $AppName = $app.App

    # Разворачиваем строки From и To с подстановкой $AppName
    $rawFrom = $app.From -replace '\$AppName', $AppName
    $rawTo   = $app.To   -replace '\$AppName', $AppName

    # Разворачиваем переменные окружения
    $from = $ExecutionContext.InvokeCommand.ExpandString($rawFrom)
    $to   = $ExecutionContext.InvokeCommand.ExpandString($rawTo)

    # Если путь To относительный, делаем его абсолютным относительно пользователя
    if (-not [System.IO.Path]::IsPathRooted($to)) {
        $to = Join-Path $env:USERPROFILE $to
    }

    Write-Host "=============================="
    Write-Host "Processing $AppName with action $action (Type=$($app.Type))"
    Write-Host "  Raw From: $rawFrom"
    Write-Host "  Raw To  : $rawTo"
    Write-Host "  Expanded From: $from"
    Write-Host "  Expanded To  : $to"

    # Обработка isolate: выполняем подскрипт вместо симлинков
    if ($app.Type -eq "isolate") {
        if ($app.Script) {
            # Шагово: сначала подставляем $AppName
            $scriptRaw = $app.Script -replace '\$AppName', $AppName
            # Потом заменяем $Apps на путь $apps (если опечатка в CSV)
            $scriptRaw = $scriptRaw -replace '\$apps', $apps
            # Теперь расширяем оставшиеся vars (env и т.д.)
            $scriptPath = $ExecutionContext.InvokeCommand.ExpandString($scriptRaw)
        } else {
            # Fallback без Script
            $safeName = $AppName -replace ' ', '_'
            $scriptPath = Join-Path $apps "$safeName.ps1"
        }
        
        Write-Host "    Isolate mode: Executing script $scriptPath"
        if (Test-Path $scriptPath) {
            try {
                # Передаём action и app-контекст в подскрипт
                & $scriptPath -Action $action -AppName $AppName -From $from -To $to
            } catch {
                Write-Error "Script failed for $AppName`: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Isolate script not found: $scriptPath"
        }
        continue  # Пропускаем симлинки
    }

    switch ($action.ToLower()) {
        "disconnect" {
            Write-Host "    Removing $to"
            if (Test-Path $to) { Remove-Item $to -Recurse -Force }
        }
        "connect" {
            Write-Host "    Creating symlink $to -> $from"
            if (-not (Test-Path $to)) {
                New-Item -Path $to -ItemType SymbolicLink -Value $from | Out-Null
            }
        }
        "reconnect" {
            Write-Host "    Removing $to"
            if (Test-Path $to) { Remove-Item $to -Recurse -Force }
            Write-Host "    Creating symlink $to -> $from"
            if (-not (Test-Path $to)) {
                New-Item -Path $to -ItemType SymbolicLink -Value $from | Out-Null
            }
        }
        default {
            Write-Warning "Неизвестное действие: $action"
        }
    }
}
