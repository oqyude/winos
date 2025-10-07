param(
    [string]$action = "reconnect"  # connect | disconnect | reconnect
)

Write-Host "Apps Manager запущен с действием: $action"

# CSV-файл с приложениями
$config = $appsAll

# Импорт CSV
$apps = Import-Csv -Path $config

foreach ($app in $apps) {
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

    if ($app.Type -ieq "isolate") {
        Write-Host "  [isolate] — пропускаем действия"
        continue
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
