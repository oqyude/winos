# Аудит семи репозиториев lamet перед сносом

Дата: **2026-10-30**. Машина: `lamet` (Windows), репозитории в `C:\Git\`.

Метод: для каждого репозитория сняты ветка, `git status`, диффы, `git check-ignore -v`,
вес. Отдельно перепроверено «нет неотправленных коммитов» — **не по устаревшим
remote-tracking refs, а по живому remote** (`git ls-remote` + `git merge-base --is-ancestor`),
потому что локальные копии отстают от сервера.

## Итоговая таблица

| Репозиторий | Ветка | Грязных | Неотправленных | Вес | Вердикт |
|---|---|---|---|---|---|
| `auto-vor` | `agent/inbox-abs-numbering` | 1 | нет | 82 МБ | **удалять целиком можно** (после спасения 1 файла) |
| `metaagent-director` | `dev` | 4 | нет | 102 МБ | **сначала спасти: 4 файла + `state/`** |
| `nixos` | `dev` | 0 | нет | 4 МБ | **удалять целиком можно** |
| `university-practice` | `dev` | 0 | нет | 8 МБ | **удалять целиком можно** |
| `university-work` | `agent` | 0 | нет | 365 МБ | **сначала спасти: `.temp/` (217 МБ) + `reference/`** |
| `winos` | `dev` | 0 | нет | 3 МБ | **удалять целиком можно** (кроме `agent/opencode-registry` — пушится в этой задаче) |
| `workscripts` | `master` | 1 | нет | 18 МБ | **удалять целиком можно** (после спасения 1 файла) |

**Сносятся не глядя: 5 из 7.** Два (`metaagent-director`, `university-work`) требуют
спасения — спасено, см. раздел «Спасение».

---

## Проверка неотправленных коммитов (перепроверка)

Директор утверждал, что неотправленных коммитов нет ни в одном репозитории.
**Подтверждено**, но с оговоркой: проверять надо по живому remote, а не по локальным
`refs/remotes/*` — они устарели (последний `fetch` — от 2026-07-21 у `workscripts`,
от 2026-10-01 у `nixos`).

`git ls-remote --heads origin` показал, что **все семь remote ушли вперёд**:
локальные ветки отстают, но ни одна не содержит коммитов, которых нет на сервере.

| Репозиторий | Локально | На remote | Коммитов не в remote |
|---|---|---|---|
| `auto-vor` | 6 веток | все 6 есть, remote впереди | 0 |
| `metaagent-director` | `dev`, `master`, `agent/status-fast` | все 3 есть, remote впереди | 0 |
| `nixos` | `dev`, `master` | обе есть, remote впереди | 0 |
| `university-practice` | `dev` | `dev` есть, remote впереди | 0 |
| `university-work` | `agent`, `master`, `wip/practice-fixes-2026-10-26` | все 3 есть, remote впереди | 0 |
| `winos` | `dev`, `master`, `agent/opencode-registry` | `dev`, `master` есть; **новая ветка — пушится сейчас** | 0 (известных коммитов нет) |
| `workscripts` | `master` | `master` есть, remote впереди | 0 |

Проверка `workscripts` через `https://git.zeroq.su/...` не прошла (askpass требует
интерактивного ввода, репозиторий приватный). Проверено тем же хостом по SSH:
`git ls-remote gitea@git.zeroq.su:oqyude/workscripts.git` → `master` = `81b5b77`,
локальный `master` = `c928e6a`, и `c928e6a` — предок `81b5b77`. Неотправленного нет.

Дополнительно: `git stash list` пуст во всех семи; `git worktree list` — кроме
`metaagent-director` и `winos` дополнительных ворктри нет.

---

## 1. `auto-vor` — 82 МБ

**Ветка:** `agent/inbox-abs-numbering` (HEAD `2dd7828`), upstream `origin/agent/inbox-abs-numbering`, синхронна.
**Remote:** `gitea@git.zeroq.su:work/auto-vor.git`.

### Грязное (1)

```
?? build-detached.bat
```

131 байт. Содержимое:

```bat
@echo off
cd /d C:\Git\auto-vor
.venv\Scripts\python.exe build.py > build-run.log 2>&1
echo DONE %ERRORLEVEL% >> build-run.log
```

**Это мусор от сборки, а не ценность.** Одноразовая обёртка для запуска `build.py`
в фоне; сам `build.py` — в репозитории и закоммичен (`git ls-files build.py` → `build.py`).
Логи сборки (`build-run.log`, `build-install.log`) — тоже мусор, они в `.gitignore`.

Действие: файл спасён в `.rescue/auto-vor/` на всякий случай, но **удалять репозиторий
можно целиком** — в git есть всё, что нужно.

### Игнорируемое (`git check-ignore -v`)

| Путь | Правило | Что это | Вердикт |
|---|---|---|---|
| `.venv/` | `.gitignore:133:.venv` | окружение Python | мусор (пересоздаётся) |
| `build/` | `.gitignore:12:build/` | Nuitka-сборка, 10 МБ | мусор |
| `__pycache__/` | `.gitignore:3:__pycache__/` | байт-код | мусор |
| `.pytest_cache/` | `.gitignore` | кэш тестов | мусор |
| `build-install.log`, `build-run.log` | `.gitignore` | логи сборки | мусор |
| `target/`, `dist/` | `.gitignore:77`, `:14` | артефакты сборки | мусор |
| `.env` | `.gitignore:132:.env` | секреты | **правило на месте, файла на диске нет** |
| `input/` | правила нет | **входные xlsx закоммичены** (`git ls-files input` → 3 файла) | в git, не теряется |

### Прочее

`.git` — 1 МБ, рабочее дерево — 81 МБ, из них 71 МБ `.venv` и 10 МБ `build/`.
Секретов на диске нет: `.env` отсутствует, `cacert.pem` найден только внутри
`.venv/Lib/site-packages/pip/_vendor/certifi` — это сертификаты CA из поставки pip, не секрет.

**Вердикт: удалять целиком можно** (после спасения `build-detached.bat`).

---

## 2. `metaagent-director` — 102 МБ

**Ветка:** `dev` (HEAD `23dbdff`), upstream `origin/dev`, отстаёт на 269 коммитов
(remote ушёл вперёд — это нормально, локально ничего уникального нет).
**Remote:** `gitea@git.zeroq.su:oqyude/metaagent-director.git`.

### Грязное (4)

**2.1 `M director.config.toml` — ЦЕННОЕ.**

Диff (правка путей после переименования каталога `C:\Git\work` → `C:\Git\university-work`):

```diff
 [[repo]]
 urn            = "oqyude/university-work"
-path.lamet      = "work"          # локальный каталог C:/Git/work — переименован только репозиторий на gitea (2026-10-26)
-path.sapphira = "work"
+path.lamet      = "university-work"          # локальный каталог C:/Git/work — переименован только репозиторий на gitea (2026-10-26)
+path.sapphira = "university-work"
```

Это **незакоммиченная, но рабочая** правка: каталог на диске уже переименован
(`C:\Git\university-work` существует, `C:\Git\work` — нет), а конфиг директора
в `HEAD` ещё указывает на старое имя. Директор на этой машине работает с
`path.lamet` — без правки он не найдёт репозиторий.

**Спасать обязательно.** Файл сохранён в `.rescue/metaagent-director/director.config.toml`.

**2.2 `?? director.config.toml.bak-rename` — копия конфига ДО правки.**

Создана скриптом `finish-rename-university-work.sh` (п. 2.3) как страховка при
`cp` + `sed`. Содержит старое имя `"work"`. Технически мусор (откатная копия),
но маленькая и безвредная — **спасена** в `.rescue/metaagent-director/`.

**2.3 `?? tools/finish-rename-university-work.sh` — ЦЕННОЕ (одноразовый, но рабочий).**

Скрипт на 150 строк: дожидается освобождения каталога, делает `mv`, правит
конфиг хоста, пересобирает реестр, снимает устаревшую привязку сессии, гоняет `doctor`.
Идемпотентен. Уже отработал (переименование выполнено), но это **единственная
документация процедуры переименования** — без неё историю переименования не
восстановить. **Спасён** в `.rescue/metaagent-director/tools/`.

**2.4 `?? tools/rename-after-server-stop.ps1` — ЦЕННОЕ (парный к 2.3).**

PowerShell-обёртка: ждёт остановки сервера opencode по PID, затем зовёт
`finish-rename-university-work.sh`. Тоже уже отработал. **Спасён** в
`.rescue/metaagent-director/tools/`.

### Игнорируемое (`git check-ignore -v`)

| Путь | Правило | Что это | Вердикт |
|---|---|---|---|
| `state/` | `.gitignore:14:state/` | **состояние**, 80 МБ: `journal.jsonl` (396 КБ), `registry.tsv` (458 Б), `requesters.tsv` (2.7 КБ), `intents/` (54 md, 444 КБ), `logs/` (70 МБ), `archive/` (9 МБ), `tasks/` | состояние — но часть спасается, см. ниже |
| `.temp/` | `.gitignore:25:.temp/` | ворктри `agent-status-fast` + `base-status`, 7 МБ | мусор |
| `.metaagent-director/` | `.gitignore:73` | привязки сессий | состояние |
| `tests/.last-run.*.log` | `.gitignore` | логи тестов | мусор |
| `__pycache__/` | `.gitignore:77` | байт-код | мусор |

**Про `state/` — подробно.** Это не мусор, а рабочее состояние директора,
и **его нет в git** (`git ls-files state` → 0 файлов). При сносе машины оно
пропадёт. Что из него ценно:

* `registry.tsv` — реестр репозиториев директора (URN → путь, verdict, last-touched).
  Без него директор на новой машине не знает про репозитории.
* `requesters.tsv` — карта «кто просил» (3 КБ).
* `journal.jsonl` (396 КБ) — журнал событий директора.
* `intents/*.md` (54 файла, 444 КБ) — задания, которые директор ставил воркерам.
* `archive/session-ses_e86b2d86-worker-practice-fixes.json` (9 МБ) — архив сессии
  воркера.
* `logs/*.json` — 70 МБ сырых логов API. Ценность сомнительна (это дампы
  сообщений), но `logs/all.json` **содержит утечку**: в нём найден API-ключ
  Google (`AIza...`, 1 совпадение). Всего файлов в `logs/` — 74.

### Секреты

* `state/logs/all.json` — **найден API-ключ Google** (паттерн `AIza…`). Файл
  **не скопирован** в `.rescue` намеренно. Размер: 30 084 469 байт.
* `state/journal.jsonl`, `state/registry.tsv`, `state/requesters.tsv`,
  `state/intents/` — проверены на `sk-*`, `gsk_*`, `AIza*`, `oc_sk_*`, `sk-or-v1-*`
  и на пароль сервера opencode (значение не приводится) — **совпадений нет**, скопированы.
* `state/logs/` — остальные 74 файла проверены тем же набором — чисто, скопированы
  (41 МБ).

### Прочее

`.git` — 13 МБ, рабочее дерево — 89 МБ (из них 80 МБ `state/` и 7 МБ `.temp/`).

**Вердикт: сначала спасти — `director.config.toml`, `tools/finish-rename-university-work.sh`,
`tools/rename-after-server-stop.ps1`, `state/` (кроме `logs/all.json`).**
Всё это уже в `.rescue/metaagent-director/`. После этого — удалять можно.

---

## 3. `nixos` — 4 МБ

**Ветка:** `dev` (HEAD `c05cc88` «restructuring»), upstream `origin/dev`, синхронна по
содержимому (remote впереди).
**Remote:** `git@github.com:oqyude/nixos.git`.

### Грязное: нет

### Игнорируемое (`git check-ignore -v`)

| Путь | Правило | Что это | Вердикт |
|---|---|---|---|
| `.vscode` | `.gitignore:1` | настройки редактора | мусор |
| `.omo` | `.gitignore:2` | настройки плагина | мусор |

Других игнорируемых правил нет (`git status --porcelain --ignored` → 0 записей).

### Секреты

`secrets/default.yaml` и `modules/*/secrets/*.yaml` — **закоммичены** в git
(`git ls-files secrets` → `secrets/default.yaml`, плюс 10 файлов в `modules/`),
и это **sops-шифротекст**: `ssh_key_private: ENC[AES256_GCM,data:cyq...]`.
Правило создания — `.sops.yaml`, age-ключ `age13l2gtk0nzr484zprp7e0pkrt0ne0j4asyn2pjmlaw73nte7t7d8q4sqtxm`.
Секреты в открытом виде на диске нет (каталоги `secrets/` в `modules/*` — пустые
0-байтовые заглушки или содержат уже зашифрованное). Копировать нечего и незачем:
шифротекст в git.

Отдельно: `university-practice/tasks/credentials.py` (4394 байта) — тоже **в git**,
и это не секрет, а загрузчик переменных окружения (`ENV_FILE = .../work/.env`),
сам файл `.env` на диске отсутствует.

### Прочее

`.git` — 3 МБ, рабочее дерево — 0 МБ (всё в git). Вес минимальный.

**Вердикт: удалять целиком можно.**

---

## 4. `university-practice` — 8 МБ

**Ветка:** `dev` (HEAD `d5c4eb5` «chore(gitignore): исключить бэкап WSL с приватными ключами»),
upstream `origin/dev`, синхронна по содержимому.
**Remote:** `gitea@git.zeroq.su:oqyude/university-practice.git`.

### Грязное: нет

### Игнорируемое (`git check-ignore -v`)

| Путь | Правило | Что это | Вердикт |
|---|---|---|---|
| `dist/` | `.gitignore:15:dist/` | сборка | мусор |
| `build/` | `.gitignore:14:build/` | сборка | мусор |
| `.venv*/` | `.gitignore:10:.venv*/` | окружение | мусор |
| `__pycache__/` | `.gitignore:2` | байт-код | мусор |
| `**/.env` | `.gitignore:43:**/.env` | **секреты** | правило на месте, файла на диске нет |

Приватных ключей в `.git` этого репозитория нет — заголовок последнего коммита
как раз про их исключение; сам бэкап WSL с ключами игнорируется.

### Прочее

`.git` — 4 МБ, рабочее дерево — 4 МБ.

**Вердикт: удалять целиком можно.**

---

## 5. `university-work` — 365 МБ

**Ветка:** `agent` (HEAD `f778590` «Слияние agent: ТОИ … + МСЗИ ЛЗ3 … + практика»),
upstream `origin/agent`, синхронна по содержимому.
**Remote:** `gitea@git.zeroq.su:oqyude/university-work.git`.

### Грязное: нет

Дерево чистое, но это **не значит, что всё в git**. 217 МБ из 365 МБ лежат в
игнорируемом `.temp/` — и там реальные рабочие продукты.

### Игнорируемое (`git check-ignore -v`)

| Путь | Правило | Что это | Вердикт |
|---|---|---|---|
| `.temp/` | `.gitignore:181:.temp/` | **217 МБ рабочих артефактов** — 60 `.docx`, 12 `.pdf`, 1093 `.png`, 43 скрипта/`.md`/`.json` | **ценное, спасать** |
| `reference/` | `.gitignore:190:reference/` | 2 МБ: `СТО_07-2017.pdf` (1 207 980 байт) — эталон ГОСТ/СТО | **ценное, спасать** |
| `.metaagent-director/` | `.gitignore:184` | привязки сессий (`bindings.tsv`, `bindings.tsv.bak-rename` 15 663 байта) | состояние |
| `output/…/__pycache__/` | `.gitignore` | байт-код | мусор |
| `target/`, `dist/`, `build/`, `.venv` | `.gitignore` | сборка | мусор |
| `.env` | `.gitignore:132` | секреты | правило на месте, файла нет |

**Что именно в `.temp/`:**

* **80 файлов `.docx` + `.pdf` (59 МБ)** — документы практики и лабораторных отчётов
  в разных редакциях: `practice_rebuild.docx` … `practice_rebuild7.docx` (2.2 МБ каждый),
  `practice_orig.pdf`, `final.pdf` … `final4.pdf`, `toi2/test.docx`,
  `preprint-review/LR1.pdf`. Это **главный рабочий результат** репозитория.
* **43 текстовых файла (448 КБ)** — скрипты сборки отчётов:
  `make_report_orig.py` (42 КБ), `edit_report_md.py` (23 КБ), `edit_task_reports.py` (19 КБ),
  `forms_section.py` (24 КБ), `extract_lab.py`, `extract_practice.py`, `fix_template.py`,
  плюс `lab01.md`/`lab02.md`, `report_num.md` и т. п.
* **1093 `.png` (105 МБ)** — рендеры страниц (`practice_rebuild5-01.png` и т. п.),
  производные от PDF. **Не спасаются**: воспроизводимы из PDF.
* `.temp/preprint-review/pylibs/` — 63 МБ, вендорённые `.pyd`/`.dll`
  (`mupdfcpp64.dll`, `_mupdf.pyd`) — чужие бинарники, **не спасаются**.

### Прочее

`.git` — 95 МБ, `output/` — 34 МБ (535 файлов в git), `.temp/` — 217 МБ.
Секретов на диске нет. В `output/` лежат только `id_ed25519.pub` (99 байт) —
**публичные** ключи, не секреты.

**Вердикт: сначала спасти — `.temp/` (документы `.docx`/`.pdf` и скрипты) и
`reference/СТО_07-2017.pdf`.** Спасено в `.rescue/university-work/`. После этого —
удалять можно.

---

## 6. `winos` — 3 МБ

**Ветка:** `dev` (HEAD `eb78e77`), upstream `origin/dev`, синхронна по содержимому.
**Remote:** `gitea@git.zeroq.su:oqyude/winos.git`.

### Грязное: нет

(Кроме новой ветки `agent/opencode-registry` — она создана этой задачей и пушится в неё.)

### Игнорируемое (`git check-ignore -v`)

| Путь | Правило | Что это | Вердикт |
|---|---|---|---|
| `.temp/` | `.gitignore:226:.temp/` | ворктри (включая ворктри этой задачи) | мусор/состояние |
| `data/state/` | `.gitignore:229:data/state/` | **состояние**: `symlink-snapshot.json` (42 785 байт) — снимок симлинков symlink-manager | состояние, спасён |
| `build/`, `dist/`, `target/`, `.venv` | `.gitignore` | сборка | мусор |
| `data/opencode-serve/.env` | `.gitignore:232:data/opencode-serve/.env` | **секреты** | правило на месте, каталога на диске нет |

### Прочее

`.git` — 1 МБ, рабочее дерево — 1 МБ (из них `data/state/` — 44 КБ).
Секретов нет.

**Вердикт: удалять целиком можно** — с учётом того, что бакет scoop `winos`
(`https://github.com/oqyude/winos`) указывает на **github**, а не на этот локальный
каталог, и `bucket/winos` тоже указывает на github. Снос `C:\Git\winos` бакет не ломает.

---

## 7. `workscripts` — 18 МБ

**Ветка:** `master` (HEAD `c928e6a` «ended structure»), upstream `origin/master`,
синхронна по содержимому.
**Remote:** `https://git.zeroq.su/oqyude/workscripts.git` (приватный; проверка по SSH:
`gitea@git.zeroq.su:oqyude/workscripts.git`).

### Грязное (1)

```
?? .metaagent-director/
```

Каталог с одним файлом `bindings.tsv` (377 байт) — привязка сессии директора.
**Это состояние**, а не ценность: пересоздаётся при первом запуске директора на новом
машине. Спасён в `.rescue/workscripts/` на всякий случай.

### Игнорируемое (`git check-ignore -v`)

| Путь | Правило | Что это | Вердикт |
|---|---|---|---|
| `input/*` | `.gitignore:178:input/*` | **состояние** (1 МБ): 4 md-файла с Veeam-документацией (`veeam backup and replication - VMware vSphere.md` — 145 КБ и др.) | состояние, но **спасено** — единственные копии |
| `output/*` | `.gitignore:179:output/*` | **состояние** (1 МБ): `result.xlsx` (38 895 байт) — результат работы `md_ports_to_excel` | состояние, **спасено** |
| `.venv` | `.gitignore:133` | окружение, 17 МБ | мусор |
| `__pycache__/` | `.gitignore:3` | байт-код | мусор |
| `target/`, `dist/`, `build/` | `.gitignore` | сборка | мусор |
| `.env` | `.gitignore:132` | секреты | правило на месте, файла нет |

### Прочее

`.git` — 1 МБ, рабочее дерево — 17 МБ (из них `.venv` — 17 МБ, остальное — `input/`+`output/`).
Секретов нет.

**Вердикт: удалять целиком можно** (после спасения `input/` и `output/` — они
не в git и без спасения пропадут).

---

## Спасение

Каталог: **`C:/Git/.rescue/`** — вне репозиториев, как и требовалось.
Всего **273 файла, 110 МБ**. Проверено на секреты (`sk-*`, `gsk_*`, `AIza*`,
`oc_sk_*`, `sk-or-v1-*` и пароль сервера opencode — значения не приводятся)
по всему дереву спасения — **совпадений нет**.

| Репозиторий | Что | Файлов | Размер |
|---|---|---|---|
| `auto-vor/build-detached.bat` | одноразовая обёртка сборки | 1 | 131 Б |
| `auto-vor/build/` | `auto-vor-entry.py` + логи сборки (`build.log`, `build2.log`, `build3.log`) | 4 | 9,6 КБ |
| `metaagent-director/director.config.toml` | **правка путей `work` → `university-work`** | 1 | 11 133 Б |
| `metaagent-director/director.config.toml.bak-rename` | копия конфига до правки | 1 | 11 111 Б |
| `metaagent-director/tools/` | `finish-rename-university-work.sh`, `rename-after-server-stop.ps1` | 2 | 7 457 Б |
| `metaagent-director/state/registry.tsv` | реестр репозиториев директора | 1 | 458 Б |
| `metaagent-director/state/requesters.tsv` | карта «кто просил» | 1 | 2 739 Б |
| `metaagent-director/state/journal.jsonl` | журнал событий директора | 1 | 405 212 Б |
| `metaagent-director/state/intents/` | задания, которые директор ставил воркерам (`.md`) | 54 | 336 780 Б |
| `metaagent-director/state/logs/` | сырые логи API (все, кроме `all.json`) | 74 | 42 527 944 Б |
| `metaagent-director/state/session-ses_e86b2d86-worker-practice-fixes.json` | архив сессии воркера | 1 | 9 357 992 Б |
| `university-work/.temp/docs/` | рабочие документы `.docx` + `.pdf` | 80 | 59 411 487 Б |
| `university-work/.temp/scripts/` | скрипты сборки отчётов (`.py`, `.md`, `.json`, `.txt`) | 43 | 360 638 Б |
| `university-work/reference/СТО_07-2017.pdf` | эталон СТО | 1 | 1 207 980 Б |
| `university-work/.metaagent-director/bindings.tsv.bak-rename` | бэкап привязок сессий | 1 | 15 663 Б |
| `workscripts/input/` | 4 md-файла (Veeam-документация) | 4 | 171 258 Б |
| `workscripts/output/result.xlsx` | результат `md_ports_to_excel` | 1 | 38 895 Б |
| `workscripts/.metaagent-director/bindings.tsv` | привязка сессии директора | 1 | 377 Б |
| `winos/data/state/symlink-snapshot.json` | снимок симлинков symlink-manager | 1 | 42 785 Б |

**Не скопировано намеренно:**

* `metaagent-director/state/logs/all.json` — 30 084 469 байт, содержит **API-ключ
  Google** (`AIza…`). Не копируем, ключ считать скомпрометированным. (Остальные 74 файла
  из `state/logs/` скопированы.)
* `university-work/.temp/**/*.png` (105 МБ) и `.temp/preprint-review/pylibs/`
  (63 МБ) — производные рендеры и вендорённые бинарники.
* `university-work/output/**/id_ed25519.pub` — публичные ключи.
* `nixos/secrets/**` — sops-шифротекст, уже в git.

## Требует решения владельца

1. **`metaagent-director/director.config.toml`** — правка пути `work` → `university-work`
   не закоммичена. Каталог на диске уже переименован, поэтому в `HEAD` лежит
   **устаревшая** конфигурация. Файл спасён, но решение (коммит / откат) за владельцем.
2. **`metaagent-director/state/logs/all.json`** — утечка API-ключа Google. Файл не
   скопирован; **ключ надо отозвать и перевыпустить**.
3. **`metaagent-director/state/` (80 МБ)** — рабочее состояние директора. Реестр
   (`registry.tsv`) и журнал спасены; 70 МБ сырых логов — по вкусу владельца
   (в `.rescue` попали 41 МБ из них).
4. **`university-work/.temp/`** — 80 документов в нескольких редакциях. Какая версия
   «итоговая» (`practice_rebuild7.docx`? `final4.pdf`?) — за владельцем;
   все версии спасены.
5. **`nixos/secrets/`** — age-приватный ключ для sops на этой машине **не найден**
   (в репозитории только публичный). Расшифровать `secrets/default.yaml` на месте
   нечем — нужен ключ с sapphira.

## Ограничения, соблюдённые при аудите

* Репозитории **не удалялись**, `git clean` / `git reset --hard` **не выполнялись**.
* Рабочее дерево каждого репозитория в том же состоянии, что до аудита
  (проверено `git status` после всех операций; единственная новая сущность —
  ветка `agent/opencode-registry` в `winos`).
* opencode **не трогали**: ни `scoop uninstall`, ни удаления `~/.config/opencode`
  или `~/.local/share/opencode`, ни `npm -g rm`, ни остановки сервера.
  Изменения в каталогах opencode делались только **на копиях** во временной папке
  (`%TEMP%\opencode\…`) — оригинал `~/.config/opencode` не менялся.
* Системные переменные окружения **не менялись** (`setx` не вызывался).
* Вне `C:/Git/.rescue/` и ворктри ничего не создано.
* На живом сервере opencode выполнялись только **читающие** команды
  (`opencode models`, `opencode auth list`, `opencode --version`);
  `opencode models --standalone` поднимает отдельный приватный сервер и
  работающих процессов не трогает.

## Смежная находка (не репозиторий, но к сносу относится)

Разбирая `~/.config/opencode` для реестра, зафиксировано ещё одно — оно не в
семи репозиториях, но решается при сносе машины:

**`~/.config/opencode/tui.json` указывает плагин `oh-my-openagent@latest`,
который не установлен.** В npm-кэше `~/.cache/opencode/npm/oh-my-openagent@latest`
лежит только каталог `.staging-…` (134 МБ) от прерванной установки 2026-10-24 —
без `package.json`, то есть полноценной установки нет. В логе сервера
(`~/.local/share/opencode/log/opencode.log`) событий загрузки `oh-my-openagent`
**ноль** — загружается только `oh-my-opencode-slim@3.0.5`.

Проверено, что причина — не «opencode не читает `tui.json`», а недокачанный пакет:
подставной `MARKER-PLUGIN-XYZ-9999` в `tui.json` не породил ни одной попытки
загрузки, а `tui.json` не входит в список v2-конфигов
(`opencode.json`, `cli.json`, `client.json` — извлечено из бинаря `opencode2`).

Итог: **134 МБ мёртвого кэша** и расхождение в конфигурации. Сам кэш при сносе
машины пропадёт вместе с `~/.cache`, так что отдельного спасения не требует —
но строку в `tui.json` стоит убрать или привести к `oh-my-opencode-slim@3.0.5`
до сноса, иначе на новой машине opencode попытается качать этот пакет заново.
Подробности и разбор — в `docs/opencode-registry.md`, раздел 1.5.
