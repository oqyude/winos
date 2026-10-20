\# Требует внимания: `merge-powerlinks..dev`



\## 🔴 Перед мержем — обязательно



\### 1. Неверная ссылка на коммит в `bee5588`



`bee5588 chore(tasks): close W10 as implemented; reference commit 57276a1` ссылается на `57276a1` как на "preceding feat(herdr-serve) commit". Но \*\*feat(herdr-serve) — это `7374f7e`\*\*, а `57276a1` — это косметический rename баннера.



Тот же текст вкратце ушёл и в `.agent/tasks/manifest.json` (W10 acceptance commentary). Читатель через полгода пойдёт по ссылке и не найдёт модуля там, куда его отправили.



\*\*Фикс:\*\* точечный edit коммит-сообщения через `git commit --amend --no-edit` после правки `manifest.json`, либо `rebase -i` с `reword`. Одна правка текста, без изменения кода.



\### 2. `$serviceAliases` — ручная identity-карта без теста на дрейф



В `main.ps1` сейчас:



```powershell

$serviceAliases = @{

&#x20;   "opencode-serve" = "opencode-serve"

&#x20;   "herdr-serve"    = "herdr-serve"

}

```



Это identity-отображение (alias → сам alias). При добавлении третьего сервиса нужно синхронно править две структуры: `$modules` (добавить запись с Alias) и `$serviceAliases` (добавить строку). Теста на их консистентность нет — классический silent drift, против которого W2 и выстраивал single-source-of-truth.



\*\*Фикс (вариант):\*\*



\- \*\*(a) Автогенерация\*\* в `main.ps1`, прямо перед `$serviceAliases = @{...}`:

&#x20; ```powershell

&#x20; $serviceAliases = @{}

&#x20; foreach ($key in $modules.Keys) {

&#x20;     if ($modules\[$key].Alias) { $serviceAliases\[$modules\[$key].Alias] = $key }

&#x20; }

&#x20; ```

&#x20; Дубль устраняется; добавление сервиса = одна правка в `$modules`.

\- \*\*(b) Оставить ручную карту, но добавить тест\*\* в `tests/main.Tests.ps1`:

&#x20; ```powershell

&#x20; It "keeps $serviceAliases aligned with $modules.Alias" {

&#x20;     $expected = @{}

&#x20;     foreach ($key in $modules.Keys) {

&#x20;         if ($modules\[$key].Alias) { $expected\[$modules\[$key].Alias] = $key }

&#x20;     }

&#x20;     $serviceAliases.Count | Should -Be $expected.Count

&#x20;     foreach ($k in $expected.Keys) { $serviceAliases\[$k] | Should -Be $expected\[$k] }

&#x20;}

&#x20; ```



Рекомендую \*\*(a)\*\* — это тот же паттерн, что уже применён к `Actions` в этом же коммите.



\---



\## 🟡 До мержa желательно



\### 3. `vars.Tests.ps1` — ассертация "у каждой записи есть Alias" проходит вакуумно



Текущий код:



```powershell

foreach ($name in $modules.Keys) {

&#x20;   $modules\[$name].ContainsKey("Alias") | Should -Be $true -Because "$name is CLI-reachable"

}

```



Сейчас у всех пяти записей Alias есть, и тест зелёный. Регрессия, при которой кто-то выпилит Alias у всех записей разом, \*\*не будет поймана\*\* — ассерт всё равно вернёт true.



Полезный инвариант: записи с глаголами `setup`/`remove` (т.е. сервисы) обязаны нести Alias, иначе двухуровневая грамматика их не достигнет.



\*\*Фикс:\*\*



```powershell

$serviceEntries = $modules.GetEnumerator() |

&#x20;   Where-Object { $\_.Value.Actions -contains 'setup' }

foreach ($entry in $serviceEntries) {

&#x20;   $entry.Value.ContainsKey('Alias') | Should -BeTrue -Because "$($entry.Key) is reachable through `service <name>`"

}

```



\### 4. `$ConfirmPreference` в `tests/modules/herdr-serve.Tests.ps1` — implicit dependency на Pester



Тест вызывает `. $scriptPath -action remove`, `. $scriptPath -action start` без явного `-Confirm:$false`. В обычном PowerShell `$ConfirmPreference = 'High'` по умолчанию, и ShouldProcess без явного `-Confirm:$false` запросил бы подтверждение. В Pester этого не происходит (я подтвердил прогоном — `Herdr Serve service removed.` и `Herdr Serve started.` печатаются, значит ShouldProcess вернул true без промпта), но это держится на негласном поведении Pester.



\*\*Фикс:\*\* в `BeforeAll` добавить одну строку:



```powershell

$ConfirmPreference = 'None'

```



Защита от изменений поведения Pester в будущем, явное намерение «в тестах промптов не будет».



\### 5. Подтянуть ли `opencode-serve.ps1` до уровня ShouldProcess-дисциплины herdr-serve?



`opencode-serve.ps1` декларирует `\[CmdletBinding(SupportsShouldProcess)]`, но `setup`/`remove`/`start`/`stop` \*\*не вызывают\*\* `$PSCmdlet.ShouldProcess(...)`. Это означает: `winos opencode-serve setup -WhatIf` фактически \*\*не делает dry-run\*\* — пишет `config.json` и регистрирует задачу.



Расхождение свежее (введено в этом же наборе коммитов), легко закрывается. Не баг-блокер, но если оставить — стоит зафиксировать в `docs/herdr-serve.md` строкой в таблице «Differences from opencode-serve»:



```

| setup -WhatIf | honours (writes nothing) | does not honour (still registers) |

```



Решение за вами. Если «да, подтягиваем» — это 4 строки в `opencode-serve.ps1` по образцу herdr-serve и один новый тест «setup with -WhatIf writes nothing» по образцу herdr-serve.Tests.ps1:111–150.



\---



\## 🟢 Можно отложить (зафиксировать в бэклоге)



\### 6. W14 — пробел в acceptance criteria



`manifest.json` для W14 пишет: «NeuralNote попадает в state/powerlinks.json через явный owner `adopt`», но в `acceptance\_criteria` W14 нет шага `adopt`. Либо добавить критерий «после создания манифеста владелец запускает `winos plugin-manager adopt` и видит NeuralNote в state/powerlinks.json», либо явно вынести `adopt` в owner-work с пометкой.



\### 7. Menu-тесты в `tests/main.Tests.ps1` — позиционно-зависимы после5-го модуля



Все четыре menu-теста теперь используют магические индексы (`"5", "3", "n", "n"`), привязанные к порядку сортировки `Config Persistence | Essentials | herdr-serve | opencode-serve | Plugin Deployment`. Добавление любого Title Case модуля (`Avatar Manager`, `Backup Manager`) сдвигает индексы и ломает все четыре теста одновременно.



Если когда-нибудь будет время — переписать на фильтрацию по display name:



```powershell

$idx = ($menuOutput | Select-String '^\\s\*\\d+\\s+Plugin Deployment').ToString().Trim() -replace '^\\s\*(\\d+).\*','$1'

```



Не горит — дисциплина индексирования остаётся за командой.



\### 8. Баннер `Plugin Deployment ::` — 7 одинаковых строк



Каждая из семи `Write-Host` в `plugin-manager.ps1` повторяет префикс. Косметика: вынести в `$banner = "  Plugin Deployment :: "` один раз в начале `switch` и переиспользовать. Снижает шум при будущих добавлениях глаголов.



\### 9. Несоответствие регистров в интерактивном меню



В меню `opencode-serve` и `herdr-serve` отображаются строчными kebab-case, тогда как `Config Persistence` / `Plugin Deployment` / `Essentials` — Title Case. Визуальный шов. Если хочется единообразия — показывать в меню Title Case (`Herdr Serve`, `Opencode Serve`), а в `$modules` хранить kebab-case ключ. Не блокирующее.



\---



\## Резюме по приоритетам



| # | Что | Где | Объём работы |

|---|---|---|---|

| 1 | Поправить ссылку на коммит | `bee5588`, `manifest.json` | 1 amend + правка текста |

| 2 | Автогенерировать `$serviceAliases` | `main.ps1` | 4 строки |

| 3 | Усилить Alias-ассерт | `tests/vars.Tests.ps1` | 3 строки |

| 4 | `$ConfirmPreference = 'None'` в BeforeAll | `tests/modules/herdr-serve.Tests.ps1` | 1 строка |

| 5 | Решить по ShouldProcess в opencode-serve | `opencode-serve.ps1` + тест ИЛИ `docs/herdr-serve.md` | 4 строки + 1 тест ИЛИ 1 строка в таблице |



Остальное — бэклог.

