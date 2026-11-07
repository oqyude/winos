<#
.SYNOPSIS
    Проверка состояния задачи "opencode-serve": жив ли сервер, в какой сессии,
    работает ли watchdog, нет ли висящих флагов остановки.

.DESCRIPTION
    Только чтение: ничего не запускает и не останавливает.
    Права администратора не нужны.

.EXAMPLE
    powershell -NoProfile -File .\verify.ps1
    powershell -NoProfile -File .\verify.ps1 -PublicUrl https://vetymae.opencodes.zeroq.su/
#>
[CmdletBinding()]
param(
    [string] $TaskName  = 'opencode-serve',
    [int]    $Port      = 4096,
    [string] $PublicUrl = ''
)

# при перенаправлении в файл/пайп отдаём UTF-8 (в интерактивной консоли
# PowerShell сам пишет через Unicode API, там кодировку не трогаем)
if ([Console]::IsOutputRedirected) { try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { } }

$stateDir = Join-Path $env:USERPROFILE '.local\state\oc-serve'
$ok = 0; $bad = 0
function Check($name, $cond, $detail = '') {
    if ($cond) { $script:ok++; "[ ok ] $name $detail" } else { $script:bad++; "[FAIL] $name $detail" }
}

# --- задача --------------------------------------------------------------
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Check "задача '$TaskName' существует" ($null -ne $task)
if ($task) {
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    "       state=$($task.State) logon=$($task.Principal.LogonType) lastRun=$($info.LastRunTime) lastResult=0x$('{0:X8}' -f $info.LastTaskResult)"
    Check 'задача запущена' ($task.State -eq 'Running')
    Check 'LogonType = S4U (фоновая сессия)' ($task.Principal.LogonType -eq 'S4U')
}

# --- порт и процесс -------------------------------------------------------
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
Check "порт $Port слушается" ($null -ne $listener)
if ($listener) {
    $serverPid = @($listener.OwningProcess)[0]
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$serverPid"
    "       server pid=$serverPid name=$($proc.Name) session=$($proc.SessionId) started=$($proc.CreationDate)"
    Check 'сервер в сессии 0 (окна нет)' ($proc.SessionId -eq 0)
    Check 'сервер - opencode.exe' ($proc.Name -eq 'opencode.exe')

    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.ParentProcessId)" -ErrorAction SilentlyContinue
    # лаунчер с 2026-10-29 стартует с приватной копии себя, поэтому в
    # командной строке родителя может быть .oc-serve-task.<pid>.sh
    Check 'родитель - лаунчер oc-serve-task.sh' ($parent -and $parent.CommandLine -like '*oc-serve-task*')
}

# --- watchdog (подшелл лаунчера крутит sleep 2) ---------------------------
$w1 = @(Get-CimInstance Win32_Process -Filter "Name='sleep.exe'" | Select-Object -ExpandProperty ProcessId)
Start-Sleep -Seconds 3
$w2 = @(Get-CimInstance Win32_Process -Filter "Name='sleep.exe'" | Select-Object -ExpandProperty ProcessId)
Check 'watchdog жив (sleep перезапускается)' (($w1 -join ',') -ne ($w2 -join ',')) "($($w1 -join ',') -> $($w2 -join ','))"

# --- флаги ---------------------------------------------------------------
foreach ($flag in 'stop', '.stopped') {
    $p = Join-Path $stateDir $flag
    Check "нет висящего флага $flag" (-not (Test-Path $p))
}

# --- доступность ---------------------------------------------------------
try {
    $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 10 "http://127.0.0.1:$Port/"
    Check "HTTP 127.0.0.1:$Port" ($code -eq '200') "(code=$code)"
} catch { Check "HTTP 127.0.0.1:$Port" $false }

if ($PublicUrl) {
    $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 15 $PublicUrl
    Check "HTTP $PublicUrl" ($code -eq '200') "(code=$code)"
}

# --- лог -----------------------------------------------------------------
"`n--- последние строки лаунчера в serve.log ---"
Select-String -Path (Join-Path $stateDir 'serve.log') -Pattern '^=== |^--- ' -ErrorAction SilentlyContinue |
    Select-Object -Last 6 | ForEach-Object { "  " + $_.Line }

"`nИтого: ok=$ok, fail=$bad"
if ($bad -gt 0) { exit 1 }
