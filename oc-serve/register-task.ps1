<#
.SYNOPSIS
    Устанавливает (или перерегистрирует) задачу Планировщика "opencode-serve".

.DESCRIPTION
    Копирует oc-serve-task.sh, oc-serve-common.sh, oc-serve-stop.cmd и
    oc-serve-stop.sh из этого каталога в %USERPROFILE%\.local\bin и
    регистрирует задачу, которая поднимает `opencode serve` (алиас `oc-serve`
    из ~/.bashrc) в фоновой S4U-сессии: без окна, без привязки к входу в
    систему.

    Запускать от администратора: S4U-задачу нельзя зарегистрировать из
    обычного процесса (Windows вернёт "Access denied"). Это ограничение
    действует только на регистрацию — сама задача выполняется с обычными
    (не повышенными) правами пользователя.

.EXAMPLE
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"$PWD\register-task.ps1"

.EXAMPLE
    # запуск из ssh: USERDOMAIN=WORKGROUP, домен не подставляется
    .\register-task.ps1 -User "$env:COMPUTERNAME\$env:USERNAME"

.EXAMPLE
    # снести задачу
    .\register-task.ps1 -Unregister
#>
[CmdletBinding()]
param(
    [string] $TaskName        = 'opencode-serve',
    [string] $WorkingDirectory = 'S:\Git',
    [string] $BashPath        = 'C:\Program Files\Git\bin\bash.exe',
    [string] $InstallDir      = "$env:USERPROFILE\.local\bin",
    [string] $User            = '',
    [switch] $Unregister
)

$ErrorActionPreference = 'Stop'
if ([Console]::IsOutputRedirected) { try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { } }

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw 'Нужны права администратора: перезапустите через Start-Process powershell -Verb RunAs -File <этот скрипт>'
    }
}

# Имя пользователя для принципала задачи.
# Через ssh $env:USERDOMAIN = 'WORKGROUP' — это НЕ домен, и S4U-регистрация
# падает с HRESULT 0x80070534 ("нет сопоставления имени и SID"). Локальная
# учётка называется <КОМПЬЮТЕР>\<пользователь> (VETYMAE\oqyude).
function Resolve-User {
    param([string] $Name)

    if ($Name) {
        return $Name
    }
    $domain = $env:USERDOMAIN
    if (-not $domain -or $domain -eq 'WORKGROUP') {
        $domain = $env:COMPUTERNAME
    }
    $account = $env:USERNAME
    if (-not $account) {
        throw 'Не удалось определить имя пользователя ($env:USERNAME пуст). Задайте его явно: -User <ДОМЕН>\<ПОЛЬЗОВАТЕЛЬ>'
    }
    if ($domain) { return "$domain\$account" }
    return $account
}

# Проверяем, что имя действительно сопоставляется с SID: иначе регистрация
# падает позже и с невнятным HRESULT.
function Assert-UserResolvable {
    param([string] $Name)
    try {
        $sid = ([System.Security.Principal.NTAccount]$Name).Translate([System.Security.Principal.SecurityIdentifier])
        "Пользователь: $Name (SID $sid)"
    } catch {
        throw "Имя '$Name' не сопоставляется с SID: $($_.Exception.Message). Проверьте -User (для локальной учётки это <КОМПЬЮТЕР>\<ПОЛЬЗОВАТЕЛЬ>)."
    }
}

Assert-Admin

if ($Unregister) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        "Задача '$TaskName' удалена."
    } else {
        "Задачи '$TaskName' нет."
    }
    return
}

if (-not (Test-Path $BashPath)) { throw "Не найден bash: $BashPath" }

$user = Resolve-User -Name $User
Assert-UserResolvable -Name $user

# --- 1. разложить скрипты -------------------------------------------------
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$files = 'oc-serve-task.sh', 'oc-serve-common.sh', 'oc-serve-stop.cmd', 'oc-serve-stop.sh'
foreach ($f in $files) {
    $src = Join-Path $PSScriptRoot $f
    if (-not (Test-Path $src)) { throw "Нет файла рядом со скриптом: $src" }
    Copy-Item $src (Join-Path $InstallDir $f) -Force
}
$launcher = (Join-Path $InstallDir 'oc-serve-task.sh') -replace '\\', '/'
$stateDir = Join-Path $env:USERPROFILE '.local\state\oc-serve'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
"Скрипты разложены в $InstallDir"

# Предупреждение про обновление поверх работающего экземпляра:
# bash перечитывает файл скрипта на лету, поэтому замена файла, пока
# экземпляр работает, ломает его (в логе — "syntax error ..." или rc=127).
# Новый лаунчер стартует с приватной копии и этому не подвержен; старый — подвержен.
$installed = Join-Path $InstallDir 'oc-serve-task.sh'
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task -and $task.State -eq 'Running' -and (Test-Path $installed) -and
    -not (Select-String -Path $installed -Pattern 'OC_SERVE_SELF_COPY' -Quiet -ErrorAction SilentlyContinue)) {
    ""
    "ВНИМАНИЕ: задача '$TaskName' работает со СТАРЫМ лаунчером (без приватной копии)."
    "Перезапись oc-serve-task.sh на лету ломает работающий bash — после установки"
    "остановите сервер (oc-serve-stop.sh) и запустите задачу заново:"
    "    $InstallDir\oc-serve-stop.sh ; schtasks /run /tn $TaskName"
    ""
}

# --- 2. описание задачи ---------------------------------------------------
$action = New-ScheduledTaskAction -Execute $BashPath `
    -Argument "-c `"exec $launcher 2>>$($stateDir -replace '\\','/')/serve.err`"" `
    -WorkingDirectory $WorkingDirectory

$triggers = @(
    (New-ScheduledTaskTrigger -AtStartup),
    (New-ScheduledTaskTrigger -AtLogOn -User $user)
)
$triggers[0].Delay = 'PT20S'

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType S4U -RunLevel Limited

$description = "opencode serve (алиас oc-serve) в фоновой S4U-сессии: без окна, без входа в систему. " +
               "Стоп: oc-serve-stop.cmd / oc-serve-stop.sh (не schtasks /end). Лог: $stateDir\serve.log"

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
    -Settings $settings -Principal $principal -Description $description -Force | Out-Null
"Задача '$TaskName' зарегистрирована (S4U, LeastPrivilege, пользователь $user)."

Export-ScheduledTask -TaskName $TaskName | Out-File (Join-Path $stateDir "$TaskName.task.xml") -Encoding utf8

# --- 3. напоминание -------------------------------------------------------
@"

Дальше:
  schtasks /run /tn $TaskName                 # поднять сейчас (порт 4096 должен быть свободен)
  $InstallDir\oc-serve-stop.sh               # остановить из bash/ssh
  $InstallDir\oc-serve-stop.cmd              # остановить из Windows-консоли
  schtasks /query /tn $TaskName /v /fo list    # состояние

Оба стоп-скрипта делают одно и то же: ставят флаг $stateDir\stop и ждут
освобождения порта до 20 с (код 1, если сервер не остановился).

Если сервер сейчас поднят вручную/старой версией лаунчера — сначала снимите его,
иначе новый старт увидит занятый порт и просто выйдет (rc=0).
"@ | Write-Output
