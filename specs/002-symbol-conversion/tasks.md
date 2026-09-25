---

description: "Task list for 002-symbol-conversion"
---

# Tasks: Преобразование символов из системных раскладок

**Input**: Design documents from `specs/002-symbol-conversion/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/conversion.md](./contracts/conversion.md),
[quickstart.md](./quickstart.md)

**Tests**: обязательны. Конституция 6.0.0: принцип II требует сверку эталонных раскладок, принцип
V — regression-тест для каждого изменения поведения. Внутри каждой истории тесты пишутся первыми и
должны падать до реализации.

**Organization**: задачи сгруппированы по историям спеки. Общая основа (`KeyLayout`, новый
`TextConverter` с правилом букв, подключение в `AppDelegate`) вынесена в Phase 2: без неё ни одна
история не работает.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно выполнять параллельно (другой файл, нет незавершённых зависимостей)
- **[Story]**: история спеки (US1, US2, US3)

## Path Conventions

Один SPM executable target `Sources/ReTyper/` и test target `Tests/ReTyperTests/` в корне
репозитория `/Users/maksymvakhonin/Projects/ReTyper`. Работа идёт в `main`, коммиты — только по
явному запросу владельца (конституция, процесс п. 9). Комментарии в коде — на английском.

## Общие константы для задач

Порядок клавиш по рядам клавиатуры (коды `kVK_ANSI_*`), используется в тестах сверки:

```text
number: 50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24      (` 1 2 3 4 5 6 7 8 9 0 - =)
top:    12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42      (q w e r t y u i o p [ ] \)
home:   0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39                    (a s d f g h j k l ; ')
bottom: 6, 7, 8, 9, 11, 45, 46, 43, 47, 44                      (z x c v b n m , . /)
iso:    10                                                       (§, только ISO)
```

Эталонные раскладки (ID из macOS, [R7](./research.md#r7-где-жили-ручные-таблицы-и-что-остаётся)):
`com.apple.keylayout.US`, `.ABC`, `.PolishPro`, `.German`, `.Russian`, `.RussianWin`,
`.Ukrainian`, `.Ukrainian-PC`, `.Byelorussian`. Типы клавиатуры: `40` (ANSI), `41` (ISO).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: зафиксировать исходное состояние и подготовить инструмент снятия эталонов

- [X] T001 Run `swift test` in `/Users/maksymvakhonin/Projects/ReTyper`, then create `specs/002-symbol-conversion/verification.md` with a section «Базовая линия 2026-09-25»: date, `git rev-parse HEAD`, number of executed/failed tests, macOS version (`sw_vers -productVersion`), keyboard type (`LMGetKbdType`, owner: 62 = ISO). Only facts, no PASS for anything not run
- [X] T002 [P] Create a throwaway dump helper `/tmp/retyper-probe/dump.swift` (outside the repo, never committed). For each reference layout and keyboard type `40` and `41` it prints Swift source lines `("<id>", <type>, unshifted: "<chars>", shifted: "<chars>")`. Keys follow the row order from «Общие константы» (ISO adds key `10` first). Characters come from `UCKeyTranslate` with `OptionBits(kUCKeyTranslateNoDeadKeysMask)` (the mask; `kUCKeyTranslateNoDeadKeysBit` is only the bit index 0); a key without exactly one printable non-whitespace character prints `\u{FFFD}`. Escape `"` and `\`. Reuse the code in `/tmp/retyper-probe/main.swift` (function `keyChars`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: соответствия из системы и чистая функция преобразования с прежним правилом букв.
После фазы ручные таблицы больше не участвуют в преобразовании, но физически ещё лежат в
`CharacterMap.swift` (удаляются в US3).

**⚠️ CRITICAL**: ни одна история не начинается до завершения фазы

- [X] T003 [P] Write failing tests in new `Tests/ReTyperTests/KeyLayoutTests.swift` using synthetic layouts only (no TIS):
  - `KeyboardKind(keyboardType:)`: `40/58/61` → `.ansi`, `41/59/62` → `.iso`, `42/60/63` → `.jis`, unknown value `0` → `.ansi`.
  - Key-code sets: ansi = `0...50` minus `{10, 36, 48, 49}` (47 codes); iso = ansi + `10`; jis = ansi + `93, 94`.
  - `KeyStroke` ordering: all unshifted before all shifted, then ascending `keyCode`.
  - `mapping(to:)`: collision rule. Two source keys yield the same character; the unshifted key wins over the shifted one, and a lower key code wins among keys with the same Shift state.
  - `mapping(to:)` skips keys missing in the target.
  - `Script.of`: `a`, `Z`, `ü`, `ł` → `.latin`; `ж`, `ї`, `ў` → `.cyrillic`; `×`, `÷`, `^`, `1`, `👍` → nil.
  - `script`: majority of unshifted letters (Cyrillic U+0400–U+04FF vs Latin ASCII + U+00C0–U+024F excluding `×` `÷`); a tie or no letters → `.other`.
- [X] T004 Create `Sources/ReTyper/KeyLayout.swift` per [data-model.md](./data-model.md):
  - `enum Script { case latin, cyrillic, other }` with `static func of(_ character: Character) -> Script?` (nil for non-letters). This is the single letter classifier, also used by `TextConverter`.
  - `enum KeyboardKind` with `init(keyboardType: UInt32)` via `KBGetLayoutType(Int16(truncatingIfNeeded:))`, comparing to the FourCC values `'ANSI'`, `'ISO '`, `'JIS '`; also a `keyCodes: [UInt16]` property.
  - `struct KeyStroke: Hashable, Comparable { keyCode: UInt16; shift: Bool }`.
  - `struct KeyLayout { let id: String; let keys: [KeyStroke: Character] }` with a memberwise init and computed `script`, `characters: Set<Character>` and `mapping(to:) -> [Character: Character]` (iterate `keys.keys.sorted()`, first wins).
  - Make T003 pass.
- [X] T005 Add `static func system(id: String, keyboardType: UInt32) -> KeyLayout?` to `Sources/ReTyper/KeyLayout.swift`:
  - `TISCreateInputSourceList([kTISPropertyInputSourceID: id] as CFDictionary, true)`, first result.
  - `kTISPropertyUnicodeKeyLayoutData`: return nil if missing.
  - For every code of `KeyboardKind(keyboardType:).keyCodes` and Shift off/on, call `UCKeyTranslate` with `kUCKeyActionDown`, modifier state `0` or `UInt32(shiftKey >> 8)`, the given `keyboardType` and `OptionBits(kUCKeyTranslateNoDeadKeysMask)` (not `...Bit`, which is the bit index 0).
  - Keep only results that are exactly one `Character`, not whitespace, with no scalar below `0x20` or equal to `0x7F`.
  - Doc comment: main thread only. No logging of characters.
- [X] T006 Add to `Tests/ReTyperTests/KeyLayoutTests.swift` system smoke tests:
  - `KeyLayout.system(id: "com.apple.keylayout.RussianWin", keyboardType: 41)` maps key `22`+Shift to `:` and key `10` to `ё`.
  - `KeyLayout.system(id: "com.apple.keylayout.RussianWin", keyboardType: 40)` has no key `10`, and its reverse mapping to `com.apple.keylayout.PolishPro` sends `ё` to `` ` ``.
  - A non-existent id returns nil. The installed input method `com.apple.inputmethod.SCIM.ITABC` (Pinyin, no key layout data, verified 2026-09-25) also returns nil (spec edge case «Система не отдаёт данные клавиш»).
  - If a real reference layout returns nil, the test must `XCTFail`, never `XCTSkip` (constitution, principle II).
  - `testPairBuildTime` (SC-006):
    - Warm-up: one `KeyLayout.system` call for `PolishPro` and `RussianWin` (type `41`).
    - Measured block, run under `measure {}`: load both layouts and build both `mapping(to:)` directions.
    - Additionally assert that one such build takes < 50 ms, to catch gross regressions; do not assert 5 ms, since CI machines vary.
    - The 5 ms target is checked from the release-build average in T025.
- [X] T007 Rewrite `Tests/ReTyperTests/TextConverterTests.swift` for the new API `TextConverter.convert(_:layouts:currentLayoutID:) -> ConversionResult`, covering only the letters rule. Use system layouts `PolishPro` + `RussianWin` with type `41`, plus synthetic layouts where noted. Unless stated otherwise, pass `currentLayoutID: "com.apple.keylayout.ABC"`: a layout outside the pair must not block the letters rule (FR-006).
  - `ghbdtn` → `привет`, target `RussianWin`, source `.letters`.
  - `GHBDTN` → `ПРИВЕТ`.
  - `руддщ` → `hello`, target `PolishPro`.
  - `привет w` is Cyrillic by majority.
  - Letters tie (`ab аб`, synthetic) → `targetLayoutID == nil`, `.undetermined`.
  - `Привет ^)` → letters win: result `Ghbdtn ^)` (`^` has no Cyrillic source key and stays).
  - Characters outside the main key block survive: `Ghbdtn 👍—` → `Привет 👍—` (spec edge case «Символ не набирается ни одной клавишей»).
  - Empty string, digits-only `12345` with `currentLayoutID: "com.apple.keylayout.ABC"`, and `layouts: []` → unchanged, nil target.
  - Pair selection: first Latin and first Cyrillic in the given order; German (`com.apple.keylayout.German`) is an allowed Latin target.
  - Diacritic letters count as Latin (FR-003, research R8): with German + RussianWin, `ü` → `х`, source `.letters`; with PolishPro + RussianWin, `łąś` → `converted == "łąś"` (no main-block key), source `.letters`.
  - Remove all tests that reference `CharacterMap.CyrillicLayout`, `autoConvert` or `isSupportedLatinTarget` from this file.
- [X] T008 Rewrite `Sources/ReTyper/TextConverter.swift` as `enum TextConverter`:
  - `enum DirectionSource: String { case letters, layoutOnlySymbols = "layout-only symbols", currentLayout = "current layout", undetermined }`.
  - `struct ConversionResult { converted: String; targetLayoutID: String?; source: DirectionSource }`.
  - `static func convert(_ text: String, layouts: [KeyLayout], currentLayoutID: String) -> ConversionResult`:
    1. Pick the pair: first `.latin` and first `.cyrillic` layout in `layouts`; no pair → unchanged + `.undetermined`.
    2. Count letters with `Script.of`: majority Latin → map with `latin.mapping(to: cyrillic)`, target `cyrillic.id`; majority Cyrillic → the reverse; tie → `.undetermined`.
    3. No letters → `.undetermined` for now (US1/US2 fill this in).
    4. Characters without a mapping are kept.
  - Pure, no TIS, no logging. Delete `detectScript`, `DetectedScript` and `autoConvert`. Make T007 pass.
- [X] T009 Wire the new converter in `Sources/ReTyper/AppDelegate.swift` `handleHotkey()`:
  - On the main thread, before `replacementQueue.async`: `let keyboardType = UInt32(LMGetKbdType())`, `let layouts = availableLayouts.compactMap { KeyLayout.system(id: $0, keyboardType: keyboardType) }`, `let currentLayoutID = layoutManager.currentLayoutID()` (add `import Carbon` if needed).
  - The `convert` closure calls `TextConverter.convert(text, layouts: layouts, currentLayoutID: currentLayoutID)`. It logs `Logger.shared.log("Conversion: source=\(result.source.rawValue) len=\(text.count) target=\(result.targetLayoutID ?? "none")")` (no text, FR-013) and returns `(result.converted, result.targetLayoutID)`.
  - `ReplacementFlow` stays unchanged.
- [X] T010 Run `swift test`; all tests pass. The old `Tests/ReTyperTests/CharacterMapTests.swift` still compiles against the untouched `CharacterMap.swift`.

**Checkpoint**: преобразование букв работает через системные раскладки; фрагменты без букв ещё
не меняются

---

## Phase 3: User Story 1 - Фрагмент только из символов, набранный не в той раскладке (Priority: P1) 🎯 MVP

**Goal**: `^)` → `:)`, `&` → `?`, `№` → `#`: направление по символам, которые есть только в одной
раскладке пары (FR-004)

**Independent Test**: в TextEdit при раскладке Polish набрать `^)`, двойной ⌥ → `:)`, раскладка
RU, буфер обмена прежний ([quickstart, сценарий 1](./quickstart.md#3-ручная-проверка-выполняет-владелец))

### Tests for User Story 1 ⚠️

- [X] T011 [US1] Add failing tests to `Tests/ReTyperTests/TextConverterTests.swift`. Use system `PolishPro` + `RussianWin`, type `41`, `currentLayoutID` set to an unrelated id `com.apple.keylayout.ABC` so only the symbols rule can decide:
  - `^)` → `:)`, target `RussianWin`, source `.layoutOnlySymbols`.
  - `&` → `?`.
  - `№` → `#`, target `PolishPro`.
  - `§` → `ё`.
  - `^№` (symbols of both layouts) → unchanged, nil target, `.undetermined`.
  - Letters still win: `ok ^)` → `щл :)`, `Ghbdtn^)` → `Привет:)`.

### Implementation for User Story 1

- [X] T012 [US1] In `Sources/ReTyper/TextConverter.swift` implement the no-letters step:
  - `latinOnly = latin.characters.subtracting(cyrillic.characters)` and the symmetric `cyrillicOnly`.
  - Only latin-only characters present → Latin→Cyrillic; only cyrillic-only → Cyrillic→Latin; both present → `.undetermined`; none → still `.undetermined` (US2).
  - Source `.layoutOnlySymbols`. Make T011 pass.
- [X] T013 [US1] Run `swift test`; all tests pass. Record the result in `specs/002-symbol-conversion/verification.md`.

**Checkpoint**: MVP — сценарий владельца `^)` → `:)` работает при раскладке Polish

---

## Phase 4: User Story 2 - Символы, общие для обеих раскладок (Priority: P1)

**Goal**: `:)` при раскладке RU → `^)`, повторный хоткей возвращает исходник (FR-005, FR-009)

**Independent Test**: при раскладке RU набрать `:)`, двойной ⌥ → `^)` в PL; ещё раз → `:)`
([quickstart, сценарии 2–3](./quickstart.md#3-ручная-проверка-выполняет-владелец))

### Tests for User Story 2 ⚠️

- [X] T014 [US2] Add failing tests to `Tests/ReTyperTests/TextConverterTests.swift`, system `PolishPro` + `RussianWin`, type `41`:
  - `:)` with current `RussianWin` → `^)`, target `PolishPro`, `.currentLayout`.
  - `:)` with current `PolishPro` → `Ж)`, target `RussianWin`.
  - `:)` with current `com.apple.keylayout.ABC` (not in the pair) → unchanged, nil target, `.undetermined`.
  - `)))` with current `PolishPro` → `converted == ")))"`, which `ReplacementFlow` treats as layout-only (FR-007).
  - Round trip (FR-009): for every character `c` of `latin.mapping(to: cyrillic)` whose reverse mapping returns `c`, `convert(convert(c, current: PolishPro).converted, current: RussianWin).converted == c`. Assert over the whole set, not a sample.

### Implementation for User Story 2

- [X] T015 [US2] In `Sources/ReTyper/TextConverter.swift` implement the last step for fragments without letters and without layout-only characters. `currentLayoutID == latin.id` → Latin→Cyrillic; `== cyrillic.id` → Cyrillic→Latin; otherwise `.undetermined`. Source `.currentLayout`. Make T014 pass.
- [X] T016 [US2] Run `swift test`; all tests pass. Record in `specs/002-symbol-conversion/verification.md`.

**Checkpoint**: US1 и US2 работают вместе; откат повторным нажатием работает

---

## Phase 5: User Story 3 - Соответствия берутся из реальных раскладок, выбранных в ReTyper (Priority: P1)

**Goal**: единственный источник — система. Ручные таблицы удалены, белорусский ID исправлен,
любая выбранная латинская раскладка работает. Эталонная сверка на ANSI и ISO (FR-002, FR-002a,
FR-011, SC-002)

**Independent Test**: `swift test` проходит сверку 9 эталонных раскладок на типах 40 и 41; в
`Sources/` нет словарей символов

### Tests for User Story 3 ⚠️

- [X] T017 [US3] Run `swiftc -Onone /tmp/retyper-probe/dump.swift -o /tmp/retyper-probe/dump && /tmp/retyper-probe/dump`.
  - Before copying anything, check the output against [research.md R8](./research.md#r8-расхождения-ручных-таблиц-с-macos-fr-011). Examples: RussianWin ISO has key `10` → `ё`, key `50` → `]`; RussianWin ANSI shifted key `50` → `Ë` (U+00CB); Russian shifted `22` → `,`; Ukrainian (Legacy) key `1` → `и`, key `11` → `і`; Byelorussian key `30` and shifted `30` both → `'`.
  - On any mismatch, stop and report it to the owner instead of editing the expectations.
- [X] T018 [US3] Create `Tests/ReTyperTests/KeyLayoutReferenceTests.swift`:
  - Key order constants: `static let ansiOrder: [UInt16]` = the rows `number`, `top`, `home`, `bottom` from «Общие константы» (47 codes), and `static let isoOrder = [10] + ansiOrder` (48 codes). They must match the order used by the dump helper from T002. Expectations for type `40` use `ansiOrder`, for type `41` use `isoOrder`.
  - The reviewed expectations from T017 as test data, with a comment that this is verification data, not an app mapping source. For each layout and type the test asserts that both strings have exactly as many characters as the order has codes.
  - One test iterates all 9 layouts × types `40`, `41`. It loads `KeyLayout.system`; nil → `XCTFail("reference layout missing: <id>")`. It compares every key in both Shift states with the expectation (`\u{FFFD}` = key absent from `keys`) and reports each mismatching key code.
- [X] T019 [US3] Add acceptance tests from spec User Story 3 to `Tests/ReTyperTests/TextConverterTests.swift`, using system layouts:
  - US + Russian, type `40`, current US: `^&` → `,.`.
  - German + RussianWin, type `41`, current German: `н` → `z`, target German.
  - US + Byelorussian, type `40`, current Byelorussian (so `'`, present in both layouts, is read as Cyrillic): `'` → `]`, the unshifted key wins the collision.
  - PolishPro + RussianWin, type `40`, any current: `ё` → `` ` ``, not `§`.
  - US + Ukrainian (Legacy), type `40`, any current: `ghbdsn` → `прівит`, following the real layout (research R8, verified 2026-09-25), not the old table.

### Implementation for User Story 3

- [X] T020 [US3] `git mv Sources/ReTyper/CharacterMap.swift Sources/ReTyper/LayoutCatalog.swift` and rename the type `CharacterMap` → `LayoutCatalog`.
  - Delete every mapping dictionary and reverse map, `toEnglishMap`, `fromEnglishMap`, `isSupportedLatinTarget` and the `isEnglishLayout` alias.
  - Keep the `CyrillicLayout` enum (ID + `displayName`), `cyrillicLayout(for:)`, `isLatinLayout(_:)` and `displayName(for:)`. Move the Latin names into `static let latinLayoutIDs: [String]` (full IDs, same set and order), with `isLatinLayout` using it; this lets the T022 test iterate it.
  - Change `.belarusian` raw value to `com.apple.keylayout.Byelorussian`.
  - Update the header comment: layouts offered in «Active Keyboards» and their short names; no character data.
- [X] T021 [US3] Update references in `Sources/ReTyper/LayoutManager.swift` and `Sources/ReTyper/PopoverViewController.swift`: `CharacterMap.` → `LayoutCatalog.`, `isEnglishLayout` → `isLatinLayout`. No behavior change.
- [X] T022 [US3] `git mv Tests/ReTyperTests/CharacterMapTests.swift Tests/ReTyperTests/LayoutCatalogTests.swift`.
  - Rename the class, delete all mapping-completeness, PC-difference, Ukrainian-chars and punctuation-table tests.
  - Keep the Latin/Cyrillic ID and `displayName` tests.
  - Add: `LayoutCatalog.cyrillicLayout(for: "com.apple.keylayout.Byelorussian") == .belarusian` and `displayName(...) == "BY"`.
  - Add `testEveryOfferedInstalledLayoutLoadsWithItsScript` (SC-002, second sentence):
    - Iterate every ID of `LayoutCatalog.CyrillicLayout.allCases` and `LayoutCatalog.latinLayoutIDs` (added in T020).
    - Check installation with the test's own `TISCreateInputSourceList([kTISPropertyInputSourceID: id] as CFDictionary, true)`. An ID that is not installed is skipped by name.
    - Every installed ID: `KeyLayout.system(id:keyboardType: 41)` is not nil and its `script` is `.cyrillic` for the Cyrillic group, `.latin` for the Latin group.
    - All 5 Cyrillic IDs and `US`, `ABC`, `PolishPro`, `German` must be installed; otherwise `XCTFail`.
- [X] T023 [US3] Verify no hand tables remain: `rg -n '"[a-z]": "[а-яёіїєґў]"' Sources/` and `rg -n 'CharacterMap|autoConvert|isSupportedLatinTarget|isEnglishLayout' Sources/ Tests/` return nothing. Then run `swift test`; all pass. Record in `specs/002-symbol-conversion/verification.md`.

**Checkpoint**: все три истории работают; единственный источник соответствий — macOS

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: документация и обязательные gates конституции (принцип V, процесс п. 5)

- [X] T024 [P] Update `README.md`:
  - «Supported Layouts» table: mappings come from the selected macOS layouts for the current keyboard type; list the Cyrillic IDs offered (incl. Byelorussian) and note that any offered Latin layout is a valid target.
  - Replace the limitation bullet about «US, ABC и Polish Pro» with the new rules: symbol-only fragments, direction by layout-only symbols, then the current layout; unchanged when undetermined.
  - Mention the RussianWin ANSI `Ë` quirk from research R8.
- [X] T025 Build the release candidate exactly as in [quickstart.md §2](./quickstart.md#2-release-кандидат-по-конституции-принцип-v), from the repo root:
  - Build steps:
    - full `swift test`;
    - `MACOSX_DEPLOYMENT_TARGET=12.0 swift build -c release --arch arm64`, then the same with `--arch x86_64`;
    - `lipo -create .build/arm64-apple-macosx/release/ReTyper .build/x86_64-apple-macosx/release/ReTyper -output ReTyper-universal`, then `lipo -info ReTyper-universal`, which must list `arm64 x86_64`;
    - `bash scripts/test-package-release.sh`;
    - `osascript -e 'quit app "ReTyper"'`, copy `ReTyper-universal` to `ReTyper.app/Contents/MacOS/ReTyper`, `codesign --force --sign - ReTyper.app`, then `codesign --verify --deep --strict --verbose=2 ReTyper.app`;
    - `swift test -c release --filter KeyLayoutTests/testPairBuildTime`.
  - Record in `specs/002-symbol-conversion/verification.md`:
    - each command's exact result;
    - the measured average, PASS only if ≤ 5 ms (SC-006);
    - that signing was ad-hoc because the «ReTyper Dev» identity is absent locally; CI signs with it.
  - Any failure blocks the rest.
- [X] T026 `open ReTyper.app` (the release candidate from T025, not `./build.sh`) and confirm the menu bar indicator; re-grant Accessibility and Input Monitoring if the new ad-hoc signature asks. Take a fresh screenshot of the popover with «Active Keyboards» (PL + RU) and save it as `specs/002-symbol-conversion/screenshots/popover.png`.
- [X] T027 Owner runs, on the T026 candidate, the manual scenarios from [quickstart.md §3](./quickstart.md#3-ручная-проверка-выполняет-владелец):
  - Scenarios 1–8 (no selection) in TextEdit, Safari, Telegram, Visual Studio Code and OpenChamber (SC-001).
  - Scenarios 9–11 in TextEdit and Safari: user selection, empty input, multi-type clipboard with RTF plus text (constitution, process item 5).
  - A fresh screenshot of a field after scenario 1 goes to `specs/002-symbol-conversion/screenshots/scenario-1.png`.
  - Record PASS/FAIL/not run per app and scenario in `specs/002-symbol-conversion/verification.md`; never mark unrun items as PASS.
- [X] T028 Check the **whole** log `~/Library/Caches/com.retyper.app/retyper.log` after T027 (FR-013, principle I, process item 8):
  - `Conversion: source=… len=… target=…` lines exist.
  - `grep -n -F -e '^)' -e ':)' -e 'Ghbdtn' -e 'Привет' -e 'abc' ~/Library/Caches/com.retyper.app/retyper.log` finds no user text; review any hit manually.
  - Record the result in `specs/002-symbol-conversion/verification.md`.
- [X] T029 Report to the owner from `specs/002-symbol-conversion/verification.md`: changed files, test/build/manual results and the R8 behavior changes.
  - Commit and push only after an explicit request; the suggested message is `feat: convert symbols using system keyboard layouts`. Warn before pushing: a push to `main` starts the release pipeline.
  - Before committing (constitution, process item 7): `git config user.name` must print `Jarvis` and `git config user.email` must print `jarvis.max.dev@proton.me`; otherwise stop and ask the owner. After committing, `git log -1 --format='%an <%ae> | %cn <%ce>'` must print Jarvis for both author and committer.
  - After a requested push, wait for CI of that revision (`gh run list --commit <sha>`, `gh run watch <id>`) and record the outcome in `verification.md`.
  - The feature is not done until that CI run succeeds (constitution, principle V).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: без зависимостей.
- **Foundational (Phase 2)**: после T001; T002 нужен только к T017. Блокирует все истории.
- **US1 (Phase 3)**: после Phase 2.
- **US2 (Phase 4)**: после Phase 2. Шаг «текущая раскладка» идёт после шага «символы одной
  раскладки» в той же функции, поэтому на практике — после US1.
- **US3 (Phase 5)**: после Phase 2; T017 требует T002. Не зависит от US1/US2, но общий файл
  `TextConverterTests.swift` (T019) лучше править после T014.
- **Polish (Phase 6)**: после всех историй; T027–T029 строго после T025–T026.

### User Story Dependencies

- **US1**: только Phase 2.
- **US2**: Phase 2; последовательно после US1 из-за общего `TextConverter.swift`.
- **US3**: Phase 2 и T002; от US1/US2 по логике не зависит.

### Within Each User Story

- Тесты пишутся первыми и падают до реализации.
- T020 → T021 → T022 → T023 строго последовательно: переименование ломает сборку до обновления
  ссылок.

### Parallel Opportunities

- T002 параллельно с T001 и Phase 2 (файл вне репозитория).
- T003 (тесты) параллельно с началом T004: разные файлы.
- T017–T018 (эталоны) параллельно с US1/US2: другие файлы.
- T024 (README) параллельно с T025.

---

## Parallel Example: User Story 3

```bash
# While US1/US2 edit TextConverter.swift, reference data can be prepared independently:
Task: "T017 Run /tmp/retyper-probe/dump and review against research.md R8"
Task: "T018 Create Tests/ReTyperTests/KeyLayoutReferenceTests.swift with reviewed expectations"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 + Phase 2: системные соответствия, правило букв, подключение.
2. Phase 3 (US1): `^)` → `:)`.
3. **STOP and VALIDATE**: `swift test` и сценарий 1 из quickstart у владельца.

### Incremental Delivery

1. Foundation → поведение букв как раньше, но уже из системы.
2. + US1 → символы, набранные не в той раскладке (запрос владельца).
3. + US2 → общие символы и откат повторным нажатием.
4. + US3 → удаление таблиц, белорусская раскладка, эталонная сверка, README.
5. Polish → gates конституции, ручная проверка, отчёт. Коммит — по запросу.

---

## Notes

- Не менять `ReplacementFlow.swift`, `SystemReplacementHost.swift`, `KeyboardMonitor.swift`: это
  граница фичи 001.
- Любой символ пользователя, включая результат преобразования, запрещено писать в журнал.
- Расхождение эталонов с R8 или новый провал теста — остановиться и сообщить, а не подгонять
  ожидания.
- `/tmp/retyper-probe/` — временный инструмент, в репозиторий не попадает.
