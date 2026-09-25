# Implementation Plan: Преобразование символов из системных раскладок

**Branch**: `main` (feature-ветки не обязательны, конституция, процесс п. 9) | **Date**: 2026-09-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/002-symbol-conversion/spec.md`

## Summary

Хоткей должен преобразовывать не только буквы, но и символы на тех же клавишах: `^)` → `:)` в
Russian – PC. Сейчас фрагмент без букв не преобразуется, а ручные таблицы неполны и местами
неверны ([research.md, R8](./research.md#r8-расхождения-ручных-таблиц-с-macos-fr-011)).

Подход:
- Ручные таблицы удаляются. Соответствия каждый раз строятся из данных раскладок macOS, выбранных
  в ReTyper, через `UCKeyTranslate` для текущего типа клавиатуры (конституция 6.0.0, принцип II).
- Направление по буквам определяется как сейчас. Для фрагмента без букв оно определяется по
  символам, которые есть только в одной из раскладок, а затем по текущей раскладке.
- Механизм выделения, копирования и вставки из фичи 001 не меняется.

## Technical Context

**Language/Version**: Swift 5.9 (`swift-tools-version: 5.9`)

**Primary Dependencies**: системные Cocoa и Carbon (Text Input Sources, `UCKeyTranslate`,
`LMGetKbdType`, `KBGetLayoutType`) — уже подключены в `Package.swift`; новых зависимостей нет

**Storage**: N/A — соответствия живут в памяти на время одного хоткея; `UserDefaults` без изменений

**Testing**: [XCTest](https://developer.apple.com/documentation/xctest) через `swift test`, локально
и в [GitHub Actions](https://docs.github.com/actions) `macos-14`

**Target Platform**: macOS 12.0+, Universal Binary arm64 + x86_64

**Project Type**: desktop-app (menu bar, SPM executable target)

**Performance Goals**: подготовка соответствий пары раскладок ≤ 5 мс после прогрева (SC-006;
пробный замер 1,3 мс без оптимизаций, [R3](./research.md#r3-когда-строить-соответствия-и-на-каком-потоке)).
Измеряется тестом `KeyLayoutTests.testPairBuildTime` на release-сборке, результат пишется в
`verification.md`

**Constraints**: только локальные данные; TIS-вызовы на главном потоке; преобразование — чистая
функция, пригодная для фоновой очереди; без текста в журнале

**Scale/Scope**: 2 выбранные раскладки на хоткей, около 100 клавиш × 2 состояния; 9 эталонных
раскладок × 2 типа клавиатуры в тестах

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип / правило | Как выполняется | До | После дизайна |
|---|---|---|---|
| I. Локальная обработка и приватность | Данные раскладок читаются локально из системы. В журнал попадают только источник направления, длина и ID раскладки ([R10](./research.md#r10-журнал)) | PASS | PASS |
| II. Детерминированная точность раскладок (6.0.0) | Только системные данные, ручных таблиц нет. Тип клавиатуры учитывается через набор кодов ([R1](./research.md#r1-откуда-брать-символ-клавиши), [R2](./research.md#r2-тип-клавиатуры)). Фиксированное правило коллизий ([R4](./research.md#r4-правило-коллизий)). Неопределённость — текст без изменений. Сверка 9 эталонных раскладок на ANSI/ISO; отсутствие раскладки — ошибка теста ([R9](./research.md#r9-тесты-и-ci)) | PASS | PASS |
| III. Сохранность текста и буфера обмена | `ReplacementFlow`, `SystemReplacementHost` и выбор фрагмента не меняются; меняется только замыкание `convert`. Ручная проверка в нескольких приложениях — [quickstart](./quickstart.md#3-ручная-проверка-выполняет-владелец) | PASS | PASS |
| IV. Совместимость | `UCKeyTranslate`, TIS и `LMGetKbdType` доступны на macOS 12, availability-проверки не нужны. Новых разрешений нет. Сборка arm64/x86_64 без изменений | PASS | PASS |
| V. Проверка перед релизом | Regression-тесты для каждого FR. Release-кандидат: `swift test`, arm64 + x86_64, Universal Binary через `lipo`, тест упаковки, `codesign --verify`, запуск свежего bundle, скриншот. После пуша — успешный CI публикуемой ревизии ([quickstart §2](./quickstart.md#2-release-кандидат-по-конституции-принцип-v)). Подпись сертификатом «ReTyper Dev» выполняет только CI: локально сертификата нет | PASS | PASS |
| Процесс п. 5 (поток хоткея) | Меняется `handleHotkey()`, поэтому ручные сценарии покрывают выделение пользователя, отсутствие выделения, пустой ввод и восстановление буфера из нескольких типов (RTF + текст) ([quickstart §3](./quickstart.md#3-ручная-проверка-выполняет-владелец), сценарии 1–11) | PASS | PASS |
| Процесс п. 8 (review, журнал) | Проверяется весь журнал, а не только новые строки ([quickstart §4](./quickstart.md#4-журнал)) | PASS | PASS |
| Горячий путь CGEventTap | `handleHotkey()` вызывается из callback. Tap создан с `.listenOnly`, поэтому задержка не задерживает ввод. Добавляется около 1–2 мс ограниченной работы без диска и сети; сейчас там уже есть поиск раскладок около 6 мс | PASS | PASS |
| Процесс п. 1 (спецификация) | Сценарии, раскладки, macOS, разрешения, отказы и критерии приёмки есть в spec.md | PASS | PASS |
| Процесс п. 3 (минимальность) | Две новые сущности: `KeyLayout` с данными и `TextConverter` как чистая функция. Протоколов и кешей нет | PASS | PASS |
| Процесс п. 4 (изменения преобразования) | Полный `swift test`, включая сверку эталонов, регистр, пунктуацию, направление и неопределённость | PASS | PASS |
| Процесс п. 7 (identity коммитов) | Author и committer — `Jarvis <jarvis.max.dev@proton.me>`. Локальный `git config` и три последних коммита проверены 2026-09-25. T029 повторяет проверку до и после коммита | PASS | PASS |
| Процесс п. 9 (main, коммиты по запросу) | Работа в `main`; коммит и пуш только по явному запросу | PASS | PASS |

Нарушений нет, поэтому раздел Complexity Tracking не заполняется.

Ожидаемые изменения поведения перечислены до реализации в
[R8](./research.md#r8-расхождения-ручных-таблиц-с-macos-fr-011) (FR-011, SC-004). В их числе
исправление ID белорусской раскладки ([R7](./research.md#r7-где-жили-ручные-таблицы-и-что-остаётся)).

## Project Structure

### Documentation (this feature)

```text
specs/002-symbol-conversion/
├── spec.md
├── plan.md              # этот файл
├── research.md          # Phase 0: решения, замеры, список расхождений
├── data-model.md        # Phase 1: KeyStroke, KeyboardKind, KeyLayout, LayoutPair, ConversionResult
├── quickstart.md        # Phase 1: автоматическая и ручная проверка
├── contracts/
│   └── conversion.md    # Phase 1: внешний (хоткей) и внутренний (TextConverter) контракты
├── checklists/
│   └── requirements.md
├── tasks.md             # Phase 2 (/speckit.tasks)
├── verification.md      # создаётся в T001: фактические результаты тестов, сборок, замеров и ручных сценариев
└── screenshots/         # T027–T028: свежие скриншоты popover и поля после сценария 1
```

### Source Code (repository root)

```text
Sources/ReTyper/
├── KeyLayout.swift            # NEW: KeyStroke, KeyboardKind, KeyLayout (+ .system via UCKeyTranslate), mapping(to:)
├── TextConverter.swift        # REWRITE: pure convert(_:layouts:currentLayoutID:) -> ConversionResult, DirectionSource
├── LayoutCatalog.swift        # RENAME from CharacterMap.swift: layout ID lists + displayName, maps removed, Byelorussian ID fixed
├── AppDelegate.swift          # load KeyLayouts + current layout ID on main thread in handleHotkey(); log DirectionSource
├── LayoutManager.swift        # CharacterMap → LayoutCatalog references
├── PopoverViewController.swift# CharacterMap → LayoutCatalog references
└── (ReplacementFlow.swift, SystemReplacementHost.swift, KeyboardMonitor.swift — без изменений)

Tests/ReTyperTests/
├── KeyLayoutTests.swift       # NEW: reference layouts × ANSI/ISO, key sets per keyboard kind, collision rule, missing layout = failure
├── TextConverterTests.swift   # REWRITE: direction rules on synthetic layouts; spec acceptance examples on system layouts
├── LayoutCatalogTests.swift   # RENAME from CharacterMapTests.swift: ID/displayName tests; every offered layout installed on the system loads with the matching script

└── (остальные тесты — без изменений)

README.md                      # "Supported Layouts" and the US/ABC/Polish Pro limitation rewritten for system layouts

Tools/ReTyperStand/            # added at the owner's request (2026-09-25), kept for future checks
├── Stand.swift                # own app with one NSTextView; captures only its own window (ScreenCaptureKit)
├── Driver.swift               # posts a double ⌥ only while the stand is active; checks text, layout, clipboard, log
└── run.sh                     # builds both into Tools/ReTyperStand/build/ (git-ignored) and runs scenarios 1–11
```

**Structure Decision**: один SPM executable target и один test target, как сейчас. Новый файл
только один (`KeyLayout.swift`); остальное — переписывание и переименование существующих.
`ReplacementFlow` и host не меняются: это граница фичи 001, и её ручная матрица остаётся
действительной.

## Порядок реализации (для /speckit.tasks)

1. `KeyLayout.swift` и `KeyLayoutTests`: эталоны, наборы клавиш, коллизии, отсутствие раскладки →
   ошибка теста.
2. `TextConverter` и его тесты: правила направления FR-003…FR-007, обратимость FR-009, приёмочные
   примеры спеки.
3. `LayoutCatalog`: переименование, удаление таблиц, исправление ID `Byelorussian`; обновить
   ссылки в `LayoutManager` и `PopoverViewController`; `LayoutCatalogTests`.
4. `AppDelegate.handleHotkey()`: загрузка раскладок и текущего ID на главном потоке, журнал без
   текста.
5. README: поддерживаемые раскладки и ограничения.
6. Gates по [quickstart](./quickstart.md):
   - release-кандидат: тесты, Universal Binary, упаковка, `codesign --verify`, запуск, замер;
   - ручные сценарии 1–11 в пяти приложениях и скриншоты;
   - проверка всего журнала;
   - после пуша по запросу — CI.

## Complexity Tracking

Нарушений конституции нет.
