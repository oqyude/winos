# Функциональный тест Resolve-User / Assert-UserResolvable из register-task.ps1.
# Скрипт целиком запустить нельзя (нужен админ + Планировщик), поэтому
# достаём из него только определения функций и проверяем их.
$ErrorActionPreference = 'Stop'

$path = if ($args.Count -ge 1) { $args[0] } else { Join-Path $PSScriptRoot '..\register-task.ps1' }
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path).Path, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    . ([scriptblock]::Create($fn.Extent.Text))
}

$ok = 0; $bad = 0
function Check($name, $expected, $actual) {
    if ($expected -eq $actual) { $script:ok++; "  ok   $name  -> $actual" }
    else { $script:bad++; "  FAIL ${name}: ожидалось '$expected', получено '$actual'" }
}

# --- 1. ssh-случай: USERDOMAIN=WORKGROUP -> COMPUTERNAME -----------------
$env:USERDOMAIN = 'WORKGROUP'
$env:COMPUTERNAME = 'VETYMAE'
$env:USERNAME = 'oqyude'
Check 'WORKGROUP -> COMPUTERNAME' 'VETYMAE\oqyude' (Resolve-User -Name '')

# --- 2. пустой USERDOMAIN -> COMPUTERNAME --------------------------------
$env:USERDOMAIN = ''
Check 'пустой USERDOMAIN -> COMPUTERNAME' 'VETYMAE\oqyude' (Resolve-User -Name '')

# --- 3. нормальный домен -------------------------------------------------
$env:USERDOMAIN = 'MYDOMAIN'
Check 'домен из USERDOMAIN' 'MYDOMAIN\oqyude' (Resolve-User -Name '')

# --- 4. явный -User -------------------------------------------------------
Check '-User важнее всего' 'OTHER\user' (Resolve-User -Name 'OTHER\user')

# --- 5. без COMPUTERNAME (пусто) -> только имя ----------------------------
$env:USERDOMAIN = 'WORKGROUP'
$env:COMPUTERNAME = ''
Check 'без домена и COMPUTERNAME' 'oqyude' (Resolve-User -Name '')

# --- 6. проверка сопоставления с SID: кривое имя -> понятная ошибка ------
try {
    Assert-UserResolvable -Name 'НЕТ\ТАКОГО\ЮЗЕРА'
    "  FAIL кривое имя должно было дать ошибку"; $script:bad++
} catch {
    if ($_.Exception.Message -like '*не сопоставляется с SID*') {
        "  ok   кривое имя -> понятная ошибка"; $script:ok++
    } else {
        "  FAIL неожиданная ошибка: $($_.Exception.Message)"; $script:bad++
    }
}

# --- 7. имя без домена резолвится в локального пользователя --------------
try {
    $sid = ([System.Security.Principal.NTAccount]'oqyude').Translate([System.Security.Principal.SecurityIdentifier])
    "  ok   'oqyude' -> SID $sid"; $script:ok++
} catch {
    "  skip 'oqyude' не резолвится на этой машине: $($_.Exception.Message)"
}

""
"Итого: ok=$ok fail=$bad"
if ($bad -gt 0) { exit 1 }
