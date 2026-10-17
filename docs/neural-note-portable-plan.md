# NeuralNote — данные и план portable-развёртывания

> Рабочая тема: получить portable-only-VST сборку NeuralNote v2.x без прав админа и второй копии файлов, через трекинг инсталлятора и симлинки/junction.

---

## 1. Общие данные

**Что это:** Аудио-плагин (VST3 / AU / Standalone) для транскрипции аудио → MIDI на основе MuScriptor (Kyutai/Mirelo, 103M–1.4B параметров). Полностью локальный, GPU-ускорение (Metal / Vulkan).

**Стек:** JUCE + VST3 SDK + ggml + muscriptor.cpp (как git-сабмодуль), модель в GGUF качается отдельно через Hugging Face.

**Текущая версия:** v2.1.0 (от 2026-10-13). Звёзд на GitHub: 3.2k, форков: 231.

**Лицензия:**
- Код плагина: Apache-2.0
- Веса MuScriptor: **CC BY-NC 4.0** — коммерческое использование ЗАПРЕЩЕНО. Это критично для лицензионной чистоты portable-сборки.

**Поддерживаемые платформы из коробки:** Windows x64, macOS arm64/x64. Linux — только сборка из исходников.

---

## 2. Файлы релиза v2.1.0 (8 ассетов)

Полезные дистрибутивы — 3 штуки, остальное debug-символы.

| Файл | Размер | Платформа | Назначение |
|---|---|---|---|
| [`NeuralNote_Installer_Windows_x64.exe`](https://github.com/DamRsn/NeuralNote/releases/download/v2.1.0/NeuralNote_Installer_Windows_x64.exe) | 41.7 МБ | Win x64 | Inno Setup — Standalone + VST3 |
| [`NeuralNote_Installer_Mac_arm64.pkg`](https://github.com/DamRsn/NeuralNote/releases/download/v2.1.0/NeuralNote_Installer_Mac_arm64.pkg) | 65.4 МБ | macOS Apple Si | pkg — Standalone + VST3 + AU |
| [`NeuralNote_Installer_Mac_x64.pkg`](https://github.com/DamRsn/NeuralNote/releases/download/v2.1.0/NeuralNote_Installer_Mac_x64.pkg) | 67.1 МБ | macOS Intel | pkg — Standalone + VST3 + AU |
| `NeuralNote_Installer_Windows_x64_PDBs.zip` | 40.0 МБ | Win | **debug-символы, не нужны** |
| `NeuralNote_Installer_Mac_arm64_dSYMs.zip` | 60.2 МБ | macOS | **debug-символы, не нужны** |
| `NeuralNote_Installer_Mac_x64_dSYMs.zip` | 63.2 МБ | macOS | **debug-символы, не нужны** |

[Страница релиза](https://github.com/DamRsn/NeuralNote/releases/tag/v2.1.0)

---

## 3. Стандартная установка — что куда падает

Из [`Installers/Windows/neuralnote.iss`](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/Installers/Windows/neuralnote.iss):

```
C:\Program Files\NeuralNote\                              ← Standalone-приложение
C:\Program Files\NeuralNote\NeuralNote.exe
C:\Program Files\NeuralNote\… ресурсы, DLL, uninstall…

C:\Program Files\Common Files\VST3\NeuralNote.vst3\       ← VST3-бандл
C:\Program Files\Common Files\VST3\NeuralNote.vst3\Contents\x86_64-win\NeuralNote.vst3   (DLL под расширением .vst3)
C:\Program Files\Common Files\VST3\NeuralNote.vst3\Contents\Resources\…

%APPDATA%\NeuralNote\models\                              ← runtime: GGUF веса MuScriptor
%APPDATA%\NeuralNote\                                      ← записи, настройки, логи (v2.1)
```

**Inno Setup пишет в реестр** `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{C01E3C5A-F330-421C-94D7-6264FC93B676}` — для деинсталлятора. Для работы плагина некритично, можно игнорировать.

**Деинсталлятор** (по [`CurUninstallStepChanged`](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/Installers/Windows/neuralnote.iss)) при удалении спрашивает — снести ли `%APPDATA%\NeuralNote\` тоже. Полезно знать при откате.

**macOS** (по [`Installers/Mac/NeuralNote.pkgproj`](https://github.com/DamRsn/NeuralNote/blob/main/Installers/Mac/NeuralNote.pkgproj) и README):
```
/Applications/NeuralNote.app/
/Library/Audio/Plug-Ins/VST3/NeuralNote.vst3/
/Library/Audio/Plug-Ins/Components/NeuralNote.component/   (AU)
~/Library/NeuralNote/models/                                (модели)
```

---

## 4. Состав VST3-бандла — что именно трекать

VST3 на Windows — это **папка-бандл**, а не файл. Внутри:

```
NeuralNote.vst3/
├── Contents/
│   ├── x86_64-win/
│   │   └── NeuralNote.vst3         ← собственно PE-DLL с переименованным расширением
│   ├── moduleinfo.json              ← манифест (не всегда)
│   └── Resources/
│       └── … (иконки, шрифты, soundfont-ы)
```

Шрифты и soundfont внутри VST3-папки — это `Inter`, `JetBrainsMono` (SIL OFL), `MuseScore_General` и `FluidR3Mono_GM` (MIT). Они нужны для встроенного мульти-инструментного синтa плагина — без них UI часть функционала отвалится.

**Следствие:** при portable-развёртывании нельзя просто «скопировать один файл `.vst3`» — нужна вся иерархия `Contents\…`.

---

## 5. План portable-развёртывания

### Цель
Получить работающий portable-вариант NeuralNote (минимум — VST3), который:
- не требует admin для развёртывания
- не дублирует файлы на диске (один inode = одна физическая копия)
- при обновлении централизованно подтягивает новую версию

### Целевая схема (junction для VST3)
```
C:\Program Files\NeuralNote\                         ← реальная установка (исходник)
C:\Program Files\Common Files\VST3\NeuralNote.vst3\  ← реальная установка (исходник)
       │
       │ (junction)
       ▼
D:\Portable\NeuralNote\VST3\NeuralNote.vst3\         ← виртуальный portable-путь
```

Хост типа Reaper сканирует путь `D:\Portable\…\VST3\` (прописывается в настройках) и видит плагин. Реально файлы лежат в Program Files.

### Шаги

#### 5.1. Подготовка
1. Скачать `NeuralNote_Installer_Windows_x64.exe` (41.7 МБ) — он подписан SmartScreen-предупреждением, надо «More info → Run anyway».
2. Установить с дефолтными путями (Standalone + VST3 компоненты выбраны).
3. Запустить Standalone один раз — плагин предложит скачать модель MuScriptor (минимум `small` 210 МБ; для продакшна — `medium` 620 МБ или `large` 2.7 ГБ). Это будет лежать в `%APPDATA%\NeuralNote\models\`.

#### 5.2. Трекинг инсталлятора (если хотим манифест для своего проекта)
Запустить **`ProcMon`** (Sysinternals) с фильтром:
- `Process Name` contains `setup.exe` (или именем из Inno Setup — обычно содержит `Inno Setup` или хеш)
- `Operation` is `CreateFile` or `WriteFile` or `SetRenameInformationFile`
- Включить `Drop filtered events: No`

Сохранить CSV/PML → парсить пути назначения (`Detail` для `CreateFile` содержит итоговый путь).

Альтернативы:
- **ETW File Provider** через `xperf` (быстрее, без драйверов).
- **Своя DLL-перехватка на CreateFileW** (если проект умеет инжектить в известные процессы).
- **Снимок диска до/после** (`Get-ChildItem -Recurse -Force | Get-FileHash` — тупо, но работает).

#### 5.3. Создание portable-структуры через junction
После установки выполнить:
```cmd
:: Standalone-папку — целиком как junction
mklink /J "D:\Portable\NeuralNote\Standalone" "C:\Program Files\NeuralNote"

:: VST3-бандл — целиком как junction  
mklink /J "D:\Portable\NeuralNote\VST3\NeuralNote.vst3" "C:\Program Files\Common Files\VST3\NeuralNote.vst3"
```

`/J` — directory junction, не требует admin, работает с Vista.

#### 5.4. Альтернатива через hard links (если нет доверия к junction)
Для каждого файла из манифеста инсталлятора:
```cmd
fsutil hardlink create "D:\Portable\NeuralNote\VST3\NeuralNote.vst3\Contents\x86_64-win\NeuralNote.vst3" ^
                                "C:\Program Files\Common Files\VST3\NeuralNote.vst3\Contents\x86_64-win\NeuralNote.vst3"
```
Не требует admin, но идентичные inodes создаются на каждый файл, структуру каталогов — воссоздавать отдельно.

#### 5.5. Настройка хоста (DAW)
- **Reaper**: Options → Preferences → Plug-ins → VST → add path `D:\Portable\NeuralNote\VST3\` → Re-scan.
- **Ableton**: в стандартной поставке сканирует только `%COMMONPROGRAMFILES%\VST3\`, для кастомного пути нужен `.vst3` именно там (или symbolic link, требующий admin/Developer Mode).
- **Bitwig**: Settings → Locations → Plug-ins → VST3 — добавить путь.
- **FL Studio**: Wrapper settings → Additional search paths.

#### 5.6. Модели (отдельно)
- Скопировать `%APPDATA%\NeuralNote\models\` в `D:\Portable\NeuralNote\models\` (для совсем-портатив-сценария).
- Установить переменную окружения `NEURALNOTE_MODELS_DIR=<путь>` (если плагин её поддерживает — **проверить, не документировано, по исходникам неочевидно; в README только дефолтные пути**).

Если переменную не поддерживает — модели оставлять в `%APPDATA%` или делать junction и этой папки.

---

## 6. Интеграция с проектом-трекером

### Что должен отдавать трекер (минимальный контракт)
```json
{
  "product": "NeuralNote",
  "version": "2.1.0",
  "platform": "win-x64",
  "install_root": "C:\\Program Files\\NeuralNote",
  "components": {
    "standalone": {
      "type": "exe",
      "path": "C:\\Program Files\\NeuralNote\\NeuralNote.exe",
      "deps": ["…DLL, ресурсы папки…"]
    },
    "vst3": {
      "type": "bundle",
      "path": "C:\\Program Files\\Common Files\\VST3\\NeuralNote.vst3",
      "contents": [
        "Contents\\x86_64-win\\NeuralNote.vst3",
        "Contents\\Resources\\…"
      ]
    }
  },
  "userdata_path": "%APPDATA%\\NeuralNote"
}
```

### На что смотреть в проекте
- Наблюдатель должен различать **создание файлов от инсталлятора** vs от уже работающего плагина (первый запуск Standalone после установки создаёт модели, логи, и т.д. — это не часть установки, не путать с инсталляцией).
- AppID в Inno Setup статический: `{C01E3C5A-F330-421C-94D7-6264FC93B676}` — можно фильтровать по записям в реестре для cross-check.
- Версия берётся из `AppVersion` в `.iss`, в реестре пишется в `DisplayVersion`.

---

## 7. Контрольные точки (что подтвердить перед production)

1. **Лицензия CC BY-NC 4.0 на веса.** Если portable-вариант пойдёт на коммерческую работу — это прямое нарушение. Проверить Use Case.
2. **VST3-сканирование хостом** — не все DAW подхватывают VST3 из нестандартных путей, особенно без admin-прав на запись. Проверить на целевом хосте.
3. **ASIO.** На Windows standalone собран с ASIO SDK (нужна лицензия Steinberg). На portable-распространение — лицензия обязательна (`https://www.steinberg.net/developers/prorietaпsdk/`). Проверить, что в portable-сборке ASIO не компилируется без лицензии (по [`PACKAGING.md`](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/PACKAGING.md) — `cmake -DNEURALNOTE_ASIO=OFF` собирает без).
4. **Модели качаются из Hugging Face** при первом запуске. Если целевая машина без интернета — нужно руками положить `.gguf` в `%APPDATA%\NeuralNote\models\` (структура имён строгая: например `muscriptor-medium-f16.gguf`).
5. **Обновление.** Если junction → один файл обновился — обновится и portable. Если хочется иметь несколько версий рядом — junction не подходит, нужны реальные копии.
6. **Симлинки переживают перезагрузку и перенос** в пределах того же тома NTFS. Junction в том числе.

---

## 8. Полезные ссылки

### Исходники проекта
- [Репозиторий NeuralNote](https://github.com/DamRsn/NeuralNote)
- [README.md (main)](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/README.md)
- [PACKAGING.md](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/PACKAGING.md)
- [LICENSE (Apache-2.0 код)](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/LICENSE)
- [CMakeLists.txt](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/CMakeLists.txt)

### Установщик и скрипты
- [Installers/Windows/neuralnote.iss](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/Installers/Windows/neuralnote.iss) — Inno Setup-скрипт (структура файлов и пути)
- [Installers/Mac/NeuralNote.pkgproj](https://github.com/DamRsn/NeuralNote/blob/main/Installers/Mac/NeuralNote.pkgproj) — Packages-проект для macOS
- [.github/scripts/package_windows.py](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/.github/scripts/package_windows.py) — как GitHub Actions собирает инсталлятор
- [.github/workflows/build_windows.yml](https://github.com/DamRsn/NeuralNote/blob/main/.github/workflows/build_windows.yml) — workflow CI
- [Installers/readme.txt](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/Installers/readme.txt) — текст, который показывает инсталлятор
- [Installers/license.txt](https://raw.githubusercontent.com/DamRsn/NeuralNote/main/Installers/license.txt) — текст лицензии инсталлятора

### Релизы
- [Страница релизов](https://github.com/DamRsn/NeuralNote/releases)
- [v2.1.0 (latest)](https://github.com/DamRsn/NeuralNote/releases/tag/v2.1.0)
- [v2.0.0](https://github.com/DamRsn/NeuralNote/releases/tag/v2.0.0)

### Модели и зависимости
- [DamRsn/muscriptor-gguf (Hugging Face)](https://huggingface.co/DamRsn/muscriptor-gguf) — GGUF-веса MuScriptor (CC BY-NC 4.0)
- [MuScriptor (оригинал, Kyutai)](https://github.com/muscriptor/muscriptor)
- [muscriptor.cpp (порт на C++/ggml)](https://github.com/DamRsn/muscriptor.cpp)
- [JUCE](https://juce.com/)
- [VST3 SDK](https://github.com/steinbergmedia/vst3sdk)

### Внешние ресурсы для справки
- [Sysinternals ProcMon](https://learn.microsoft.com/en-us/sysinternals/downloads/procmon) — наблюдатель файловой системы
- [Vulkan SDK](https://vulkan.lunarg.com/sdk/home) — для GPU-ускорения на Win/Linux
- [ASIO SDK лицензия](https://www.steinberg.net/developers/prorietaпsdk/) — Steinberg (для standalone с ASIO)
- [Inno Setup](https://jrsoftware.org/isinfo.php) — инструмент сборки самого инсталлятора NeuralNote
- [Packages (Mac)](http://s.sudre.free.fr/Software/Packages/about.html) — инструмент сборки .pkg

---

## 9. Резюме в одну строку

**Трекаем инсталлятор → получаем манифест путей → через `mklink /J` цепляем `NeuralNote.vst3\`-папку в кастомный путь хоста → портативный VST3 без копий и без admin.** С учётом CC BY-NC на модели и проверки путей сканирования целевого DAW.
