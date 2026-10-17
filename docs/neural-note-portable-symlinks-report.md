# NeuralNote — раскладка инсталлятора и схема симлинков для portable

> Источник фактов: распакован `NeuralNote_Installer_Windows_x64.exe` v2.1.0 (41 709 279 Б, sha‑контроль по `innounp`).
> Цель: подготовить манифест для winos (`S:\Git\winos`), чтобы развернуть NeuralNote как portable‑плагин через junction без копий файлов и без прав админа.

---

## 1. Что реально лежит в инсталляторе

Скрипт `innounp -v` и reconstructed `install_script.iss` (innoextract/innounp v2.71.2 читает Inno Setup 6.7.0):

| № | Размер | Путь в инсталляторе | Папка назначения (Inno `{app}` / `{commoncf}`) |
|---|---:|---|---|
| 1 | 82 214 912 | `{app}\NeuralNote.exe` | `C:\Program Files\NeuralNote\` |
| 2 | 80 | `{commoncf}\VST3\NeuralNote.vst3\desktop.ini` | `C:\Program Files\Common Files\VST3\NeuralNote.vst3\` |
| 3 | 89 335 | `{commoncf}\VST3\NeuralNote.vst3\Plugin.ico` | то же |
| 4 | 1 040 | `{commoncf}\VST3\NeuralNote.vst3\Contents\Resources\moduleinfo.json` | то же |
| 5 | 81 813 504 | `{commoncf}\VST3\NeuralNote.vst3\Contents\x86_64-win\NeuralNote.vst3` | то же |

**Итого: 6 файлов, ~163 МБ распакованных.** План `NeuralNote_Portable_Plan.md` упоминает шрифты и soundfont внутри бандла (`Inter`, `JetBrainsMono`, `MuseScore_General`, `FluidR3Mono_GM`) — **в этом инсталляторе их нет**. В v2.1.0 состав VST3‑бандла ограничен одной DLL и манифестом; это нужно учитывать при последующих обновлениях (если в новой версии появятся дополнительные файлы в `Contents\...`, манифест ниже придётся расширить).

**Дополнительно Inno Setup регистрирует** (но **не нужно для работы плагина**, можно игнорировать):
- `C:\Users\<USER>\Start Menu\Programs\NeuralNote.lnk` (через `[Icons]`)
- Возможный Desktop‑ярлык (через `[Tasks] desktopicon`)
- Ключ реестра `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{C01E3C5A-F330-421C-94D7-6264FC93B676}` — для деинсталлятора.

При portable‑развёртывании через winos **никакие из этих записей не нужны**.

---

## 2. Куда NeuralNote пишет пользовательские данные

В бинарниках нет абсолютно зашитых путей (проверено grep по `D:\…\AppData\…`, `Roaming`, `MUSCRIPTOR` в обоих исполняемых файлах — пусто). JUCE собирает путь в рантайме через `File::getSpecialLocationPath`:

- **Standalone‑конфиг, логи, пресеты:** `%APPDATA%\NeuralNote\` = `C:\Users\<USER>\AppData\Roaming\NeuralNote\`
- **Модели GGUF** (имена файлов найдены в бинарнике):
  - `%APPDATA%\NeuralNote\models\muscriptor-small-f16.gguf`
  - `%APPDATA%\NeuralNote\models\muscriptor-medium-f16.gguf`
  - `%APPDATA%\NeuralNote\models\muscriptor-large-f16.gguf`
- **Переменная `NEURALNOTE_MODELS_DIR`** — **не обнаружена** в бинарниках ни в ASCII, ни в UTF‑16LE (см. `probe7.ps1`/`probe5.ps1`). План это и отмечал как непроверенное — **подтверждено**: переменную окружения плагин не читает. Перенос моделей возможен **только** через `%APPDATA%`.

> **Следствие.** Standalone‑исполнение и VST3 **разделяют** `%APPDATA%\NeuralNote\` (JUCE‑конвенция `userApplicationDataDirectory` — общий каталог для exe и vst3 обоих с `AppName=NeuralNote`). Это надо учитывать при моделировании portable: модель, скачанная из Standalone, видна VST3 в DAW, и наоборот.

---

## 3. Конвенция winos: что куда положить на `S:\Plugins`

Изучены другие манифесты в `S:\Git\winos\manifests\` и существующие каталоги в `S:\Plugins\`:

- `Stone Voices - DVerb.json` использует `VST2\...` и `VST3\...` подпапки относительно `S:\Plugins\<Vendor>\`.
- `FabFilter - Total Bundle.json` декларирует `VST2\FabFilter` → `%ProgramFiles%\VSTPlugins\FabFilter` и `VST3\FabFilter` → `%CommonProgramFiles%\VST3\FabFilter`.
- Реальная раскладка, например `S:\Plugins\FabFilter - Total Bundle\VST3\FabFilter\` — корень содержит пачку `.vst3`‑папок‑бандлов (для FabFilter). Это **источник истины**, `From` манифеста.

По этой конвенции целевая раскладка для NeuralNote:

```
S:\Plugins\NeuralNote\                                       ← корень плагина (как у других вендоров)
├── NeuralNote.exe                                           ← Standalone (из инсталлятора, файл №1)
└── VST3\
    └── NeuralNote.vst3\                                     ← VST3 bundle из инсталлятора
        ├── desktop.ini                                      (файл №2)
        ├── Plugin.ico                                       (файл №3)
        └── Contents\
            ├── Resources\
            │   └── moduleinfo.json                          (файл №4)
            └── x86_64-win\
                └── NeuralNote.vst3                           (файл №5 — DLL под расширением .vst3)
```

**Это точная 1‑в‑1 копия того, что пишет инсталлятор в `C:\Program Files\` и `C:\Program Files\Common Files\VST3\`.** Никаких переразмещений, никаких переименований.

> При первом разворачивании: один раз скопировать файлы из распаковки в `S:\Plugins\NeuralNote\…` (`robocopy /MIR` или `xcopy /E`), затем junction‑ить. Последующие апдейты достаточно пере‑копировать поверх.

---

## 4. Целевые симлинки (Junction) — что декларировать в `manifests/NeuralNote.json`

Минимальный рабочий набор для **только VST3**. Standalone + модели даны отдельно, потому что это разные роли (можно включить/выключить независимо).

### 4.1. VST3‑бандл

`S:\Plugins\NeuralNote\VST3\NeuralNote.vst3\` → `C:\Program Files\Common Files\VST3\NeuralNote.vst3\`

- **Kind:** `Junction` (по конвенции winos; `From`‑путь внутри `S:\Plugins\…`, `To` — реальное системное место, куда смотрят VST3‑хосты).
- Это **одна** junction на корне бандла — внутри VST3‑папки относительные пути сохранятся.

### 4.2. Standalone (опционально, но рекомендуется)

`S:\Plugins\NeuralNote\` → `C:\Program Files\NeuralNote\`

- **Kind:** `Junction`.
- Замечание: здесь junction ведёт на **весь корень**, и `NeuralNote.exe` попадает в `%PATH%`-аналог `%ProgramFiles%` автоматически. Для standalone‑варианта это самый чистый вариант — никаких файлов‑дубликатов.

### 4.3. Модели (опционально)

`%APPDATA%\NeuralNote\` → каталог на пользовательском/портативном диске.

- **Kind:** `Junction`. Source of truth — место, где лежат `.gguf`‑файлы (например, `S:\Plugins\NeuralNote\models\` или вообще отдельный том). Target — `%AppData%\NeuralNote\` (создаётся при первом запуске плагина; если ещё нет — junction создаст пустую, последующий запуск Standalone скачает в неё модель, и оба варианта Standalone + VST3 будут видеть одинаковые файлы).
- Допустимо использовать `From` = `S:\Plugins\NeuralNote\models\` (только файлы `.gguf`), `To` = `%AppData%\NeuralNote\models\`. Альтернатива — junction всей `%AppData%\NeuralNote\`, но это смешает пресеты/логи с моделями.

### 4.4. Черновая JSON для манифеста (готовые значения)

```json
{
  "Name": "DamRsn - NeuralNote",
  "Description": "NeuralNote v2.1.0 — audio-to-MIDI transcription (JUCE + ggml + MuScriptor). VST3 required; Standalone and userdata optional.",
  "Links": [
    {
      "From": "VST3\\NeuralNote.vst3",
      "To": "%CommonProgramFiles%\\VST3\\NeuralNote.vst3",
      "Kind": "Junction"
    },
    {
      "From": "NeuralNote.exe",
      "To": "%ProgramFiles%\\NeuralNote\\NeuralNote.exe",
      "Kind": "Junction"
    },
    {
      "From": "models",
      "To": "%AppData%\\NeuralNote\\models",
      "Kind": "Junction"
    }
  ]
}
```

Замечания к черновику:

1. **Файл vs каталог для exe.** По конвенции winos `From` — это **путь относительно корня плагина в `S:\Plugins\`**, и в большинстве существующих манифестов линкуют каталоги (`VST2\\Vendor`, `VST3\\Vendor`). Если линковать только файл, winos должен это поддерживать — стоит свериться с `Get-ManifestLinks` (см. `src/modules/plugins/common/Manifest.ps1`) и подтвердить, что линковка отдельного файла‑жёсткая ссылка / junction‑на‑файл. **Проще и безопаснее**: создать в `S:\Plugins\NeuralNote\` подкаталог `Standalone\` и класть `NeuralNote.exe` туда; тогда линк становится junction‑на‑каталог.
2. **Рекомендуемая переделка** — использует только проверенные формы и совпадает с раскладкой других манифестов:

```json
{
  "Name": "DamRsn - NeuralNote",
  "Description": "NeuralNote v2.1.0 — audio-to-MIDI. VST3 required; Standalone and models optional.",
  "Links": [
    {
      "From": "VST3\\NeuralNote.vst3",
      "To": "%CommonProgramFiles%\\VST3\\NeuralNote.vst3",
      "Kind": "Junction"
    },
    {
      "From": "Standalone",
      "To": "%ProgramFiles%\\NeuralNote",
      "Kind": "Junction"
    },
    {
      "From": "models",
      "To": "%AppData%\\NeuralNote\\models",
      "Kind": "Junction"
    }
  ]
}
```

Файловая раскладка в `S:\Plugins\NeuralNote\` под этот манифест:

```
S:\Plugins\NeuralNote\
├── Standalone\
│   └── NeuralNote.exe          ← линкуется в C:\Program Files\NeuralNote\NeuralNote.exe (через junction каталога)
├── VST3\
│   └── NeuralNote.vst3\        ← целиком бандл, линкуется в C:\Program Files\Common Files\VST3\NeuralNote.vst3
│       ├── desktop.ini
│       ├── Plugin.ico
│       └── Contents\…
└── models\                      ← опционально, junction в %APPDATA%\NeuralNote\models
    └── (после первого запуска Standalone сюда скачаются .gguf)
```

3. **Junction для Standalone целиком** проще, чем линковать только `NeuralNote.exe` — но требует, чтобы каталог `C:\Program Files\NeuralNote\` уже существовал с полным набором файлов. Так что первый шаг всё равно — разово скопировать файлы в `%ProgramFiles%`, а уже потом декларировать junction и применять. Если применяется **свежая** установка (после `innounp -x`), то `C:\Program Files\NeuralNote\` ещё пуст, и каталог будет создан файлом‑`NeuralNote.exe`, для которого junction не сработает → практичнее копировать файлы перед apply.
4. **Registry‑записей для NeuralNote не требуется.** В `[Registry]` секции `install_script.iss` нет, манифест без блока `Registry` валиден.

---

## 5. Сводный чек‑лист раскладки для `S:\Plugins\NeuralNote\`

| Логический блок | Where (source, в `S:\Plugins\NeuralNote\`) | Where (target, в системе) | Тип | Обязательно? |
|---|---|---|---|---|
| VST3 bundle (для DAW) | `VST3\NeuralNote.vst3\` | `C:\Program Files\Common Files\VST3\NeuralNote.vst3\` | Junction | **Да** |
| Standalone‑приложение | `Standalone\` (или `NeuralNote.exe` напрямую) | `C:\Program Files\NeuralNote\` | Junction | Опционально |
| Модели MuScriptor (.gguf) | `models\` | `%AppData%\NeuralNote\models\` | Junction | Опционально (Standalone сам качает) |

**Минимум**, чтобы плагин заработал в DAW — **только первая строка**.

---

## 6. Команды для первого применения (cheat‑sheet)

```powershell
# один раз: после загрузки инсталлятора, извлечь, скопировать в S:\Plugins
$dst = 'S:\Plugins\NeuralNote'
New-Item -Path "$dst\VST3\NeuralNote.vst3" -ItemType Directory -Force
Copy-Item -Recurse -Force `
    'S:\Git\work\scratch\neuralnote\extracted\{commoncf}\VST3\NeuralNote.vst3\*' `
    "$dst\VST3\NeuralNote.vst3\"
New-Item -Path "$dst\Standalone" -ItemType Directory -Force
Copy-Item -Force 'S:\Git\work\scratch\neuralnote\extracted\{app}\NeuralNote.exe' "$dst\Standalone\"
# (опц.) папка под модели
New-Item -Path "$dst\models" -ItemType Directory -Force

# затем через winos — apply с манифестом manifests/DamRsn - NeuralNote.json
winos plugin-manager apply -WhatIf   # проверить
winos plugin-manager apply          # применить (junction, без admin)
```

Проверка состояния после применения:

```powershell
Get-Item 'C:\Program Files\Common Files\VST3\NeuralNote.vst3' | Select-Object Name,Attributes,LinkType,Target
# должно быть ReparsePoint + Target = S:\Plugins\NeuralNote\VST3\NeuralNote.vst3
```

В DAW: Reaper / Bitwig — добавить путь `S:\Plugins\NeuralNote\VST3\` в список VST3‑директорий → Rescan. Ableton — только со стандартным `%COMMONPROGRAMFILES%\VST3\`, поэтому junction‑в‑это‑место достаточно (там и есть target из манифеста).

---

## 7. Контрольные находки / что проверить отдельно

1. **Нет ни `Junction`, ни `SymbolicLink`, которые winos раньше создавал только с admin — но для ссылки из `S:\` (NTFS) в `C:\Program Files\` требуется запись в корне системного диска.** Под Windows 10/11 это работает для junction **без admin** (junction имеет `0x08000000` reparse, поддерживается начиная с Vista). SymbolicLink требовал developer mode / admin; **winos, по хэндофф‑summary, теперь использует Junction** для каталогов. Для NN это не проблема: все наши цели — каталоги.
2. **Один файл‑neuralnote, который в Standalone‑корне**: если решено линковать `NeuralNote.exe` файлом, а не каталогом, winos должен это поддерживать. Проверить в `src/modules/plugins/common/Manifest.ps1` (`Get-ManifestLinks`): на что расчитан — файл или каталог. **По умолчанию предполагаю каталог** (как и у других манифестов).
3. **`%AppData%`‑junction нужен до первого запуска**: Standalone при первом запуске сам создаёт `%APPDATA%\NeuralNote\models\` — если в этот момент уже стоит junction на нашу папку, всё хорошо. Если нет — модели скачаются в системное место, **а не в portable‑путь**. Решение: или сначала создать junction (руками или через winos adopt), или просто скачать модели руками в `S:\Plugins\NeuralNote\models\`.
4. **`[InstallDelete]` секция в .iss** намекает, что инсталлятор при обновлении может удалить `C:\Program Files (x86)\NeuralNote` — старый 32‑битный путь. Это нас не касается (NN только x64), но при ручных чистках имеет смысл знать.
5. **Тестовая проверка после apply**: первый запуск Standalone предложит скачать модель; если есть интернет — по умолчанию в `%APPDATA%\NeuralNote\models\`. Если `%AppData%` уже junction‑нут, модель уйдёт туда. Если offline — положить `.gguf` вручную в `S:\Plugins\NeuralNote\models\` (под `%AppData%\NeuralNote\models\`).
6. **Лицензия CC BY-NC 4.0** на веса MuScriptor (см. план, секция 1, п.3): если portable‑вариант пойдёт на коммерческий проект — лицензия всё ещё запрещает. Проверить use case.

---

## 8. Резюме (для немедленного применения)

Для portable‑развёртывания NeuralNote v2.1.0 как VST3 на Windows нужно **три каталога‑junction**, итого:

1. `S:\Plugins\NeuralNote\VST3\NeuralNote.vst3\`  →  `%CommonProgramFiles%\VST3\NeuralNote.vst3\`  — **обязательно**
2. `S:\Plugins\NeuralNote\Standalone\`             →  `%ProgramFiles%\NeuralNote\`                  — рекомендуется
3. `S:\Plugins\NeuralNote\models\`                 →  `%AppData%\NeuralNote\models\`                — рекомендуется (для портативности моделей)

Первый пункт покрывает главное требование (плагин в DAW). Второй и третий — это удобство Standalone‑варианта и переносимости моделей.

Файлов‑симлинков внутри VST3‑бандла делать **не нужно**: бандл‑папка целиком подцепляется одной junction, иерархия `Contents\x86_64-win\…` сохраняется как часть junction.
