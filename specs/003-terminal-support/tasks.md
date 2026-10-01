---

description: "Task list for 003-terminal-support"
---

# Tasks: Преобразование текста в терминалах

> **Редакция исполнения 2026-10-01:** база 0.10.1, конституция 9.0.0.
> Технические детали ниже применяются с поправками [implementation.md](./implementation.md):
> `isSuspended`, отдельные Recorder/Context/Gate, привязка по epoch, удержание с хоткея,
> отдельный TerminalDriver вместо расширения редакторного Driver. T007/T009/T010 находятся
> в `TerminalReplacementTests.swift`. Результаты спайков и согласования S4 сохранены исторически.
> Выпуск: конституция 10.0.0 и [одноразовый гейт](./release-gate.md); ручные T028/T032
> перенесены владельцем на готовую сборку и не помечаются выполненными.

**Input**: Design documents from `specs/003-terminal-support/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/terminal-hotkey.md](./contracts/terminal-hotkey.md),
[quickstart.md](./quickstart.md)

**Tests**: обязательны. Принцип V конституции 7.0.0 требует regression-тест на каждое изолируемое
изменение поведения, принцип II — тесты на системных раскладках, где отсутствие раскладки считается
ошибкой (`XCTFail`, не `XCTSkip`). Внутри каждой истории тесты пишутся первыми и должны падать до
реализации.

**Organization**: задачи сгруппированы по историям спеки. Запоминание набранного (классификация
нажатий, фрагмент, запись в tap) — общая основа, она в Phase 2. US1 — сама замена. US2 — защитные
проверки вокруг неё. US3 — отсутствие регрессии в редакторах. **Выпускать можно только US1 и US2
вместе**: US1 без US2 не проверяет защищённый ввод и прерывание.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно выполнять параллельно (другой файл, нет незавершённых зависимостей)
- **[Story]**: история спеки (US1, US2, US3)

## Path Conventions

Один SPM executable target `Sources/ReTyper/` и test target `Tests/ReTyperTests/` в корне
`/Users/maksymvakhonin/Projects/ReTyper`. Работа в `main`; коммит, пуш и публикация — только по
явному запросу владельца (процесс п. 9). Комментарии в коде — на английском. Черновой код спайков
лежит в `$TMPDIR/opencode/retyper-003/` (`/private/var/folders/jf/96nbx4_n3ksb0p99q8_ph5xm0000gn/T/opencode/retyper-003/`),
в репозиторий не попадает. `osascript` для управления Терминалом не использовать: 2026-09-29 он
повис на запросе разрешения Automation. Окна Терминала открываются через `open -a Terminal <file>.command`.

## Общие константы для задач

Коды клавиш (`kVK_*`) и флаги:

```text
Backspace 51   Return 36   Keypad Enter 76   Tab 48   Space 49   Escape 53   Forward Delete 117
Left 123  Right 124  Down 125  Up 126   Home 115  End 119  Page Up 116  Page Down 121
Fn 63   Globe 179
Main block = KeyboardKind(keyboardType:).keyCodes (Sources/ReTyper/KeyLayout.swift)
Reset flags: .maskCommand, .maskControl, .maskAlternate, .maskAlphaShift (Caps Lock)
Ignored flags: .maskShift (selects the shifted character), .maskNonCoalesced, .maskNumericPad, .maskSecondaryFn
```

Мёртвые клавиши, измеренные 2026-09-29 на ISO (тип 62), [R3](./research.md#r3-мёртвые-клавиши):
German `{10, 24, 24S}`, French `{33, 33S, 42}`, U.S. International – PC `{22S, 39, 39S, 50, 50S}`;
у PolishPro, RussianWin, Russian, US, ABC, Ukrainian-PC мёртвых клавиш нет.

Строка zsh для терминальных проверок (`<n>` — номер, `<out>` — каталог результатов,
`<preset>` — начальное содержимое строки, обычно пустое):

```zsh
#!/bin/zsh -f
line='<preset>'; vared -p '> ' -c line; print -rn -- "$line" > '<out>/line-<n>.txt'; exit
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: зафиксировать базовую линию v0.10.0 и проверить технические допущения до кода.
Провал S1 или S4 останавливает реализацию до решения владельца.

- [X] T001 Create `specs/003-terminal-support/verification.md` with a section «Базовая линия»: date, `git rev-parse HEAD`, `sw_vers -productVersion`, keyboard type (`LMGetKbdType`), result of a full `swift test` (executed/failed counts), constitution version (7.0.0). Only facts; nothing is marked PASS unless it was run
- [X] T002 Owner records v0.10.0 behaviour before any code change, in `specs/003-terminal-support/verification.md` section «v0.10.0 в редакторах» (needed for US3, SC-007): in Visual Studio Code and WebStorm, (a) the ordinary scenario in an editor tab: type `ghbdtn`, double ⌥ → expected `привет`; (b) in the integrated terminal panel: type `ghbdtn`, double ⌥ → write down the exact line content and layout afterwards, and whether the clipboard survived. Same for Terminal.app (expected: text unchanged, layout switched)
- [X] T003 [P] Spike S1 + S2 ([quickstart §1](./quickstart.md#1-спайки-до-основной-реализации), [R4](./research.md#r4-как-ввести-исправленный-текст), [R5](./research.md#r5-сколько-символов-стирает-backspace-в-оболочке), [R6](./research.md#r6-прерывание-во-время-замены-fr-009)) with a throwaway tool `$TMPDIR/opencode/retyper-003/spike-typing.swift`:
  - It writes a `.command` file with the zsh line from «Общие константы» and opens it with `open -a Terminal`; waits until `NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal"` and then 1 s for the prompt. Posts events only while Terminal is frontmost; otherwise aborts.
  - Case A: preset `ghbdtn`; post 6 × Backspace (key 51, 1 ms hold), then `привет` one character per event pair: `CGEvent(keyboardEventSource:virtualKey:0,keyDown:)` + `keyboardSetUnicodeString`, empty flags, 1 ms hold; then Return. Expect the file to contain `привет`.
  - Case B: preset `привет`; 6 × Backspace; Return. Expect an empty file (one Backspace removes one Cyrillic code point).
  - Case C (S2): preset of 100 × `a`; measure wall time of 100 × Backspace + 100 × `ж` series; Return. Expect exactly 100 × `ж` and time < 1 s.
  - Record results and timings in `specs/003-terminal-support/verification.md` section «Спайки». If case A fails (Terminal ignores the Unicode string), stop and ask the owner whether to use the clipboard fallback from R4
- [X] T004 [P] Spike S3 ([R1](./research.md#r1-как-узнать-какой-символ-напечатан)) with `$TMPDIR/opencode/retyper-003/spike-layout.swift`: a listen-only tap for `keyDown` that reads the current input source ID in the callback. The tool selects `com.apple.keylayout.RussianWin` via `TISSelectInputSource`, waits 10–50 ms, posts key 0 (to its own window or with no text field focused), and compares the ID seen in the callback with RussianWin; then the same back to PolishPro. 10 attempts each way; restore the original layout at the end. Record in `verification.md`. If any attempt sees the old layout, record it and propose a fix (for example, refresh on `kTISNotifySelectedKeyboardInputSourceChanged`) before T012
- [X] T005 [P] Spike S4 ([R7](./research.md#r7-защищённый-ввод-и-пароли-fr-007)) with `$TMPDIR/opencode/retyper-003/spike-secure.swift`, no password is typed:
  - `.command` A runs `read -s x`; after 1.5 s the tool runs `ioreg -l -w 0` and extracts `kCGSSessionSecureInputPID`, then prints `IsSecureEventInputEnabled()`; then posts Return.
  - `.command` B runs `sudo -k; sudo -v`; same checks at the password prompt; then posts ⌃C (key 8 with `.maskControl`).
  - The spike also installs a listen-only `keyDown` tap and, while `read -s` waits, posts key 0 three times: the tap must receive **none** of them (this is what keeps password characters out of the fragment). Record the count.
  - Success: both cases report the Terminal PID (`pgrep -x Terminal`) and `true`, and the tap count is 0. Record in `verification.md`.
  - If either case does not enable secure input, **stop** and ask the owner: password characters would enter the fragment (FR-007)
- [X] T006 Gate: in `specs/003-terminal-support/verification.md` write the decision «продолжать / стоп» based on T003–T005, with the reason. Continue only if S1 case A/B, S2 and S4 passed (S3 may pass with a recorded fix)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: ReTyper запоминает, что пользователь печатает в Терминале, и сбрасывает запомненное
по таблице [R2](./research.md#r2-какие-нажатия-пополняют-фрагмент-какие-сбрасывают). Хоткей пока
ведёт себя как в v0.10.0.

**⚠️ CRITICAL**: ни одна история не начинается до завершения фазы; фаза начинается только после T006 = «продолжать»

- [X] T007 [P] Add failing tests to `Tests/ReTyperTests/KeyLayoutTests.swift` (keyboard type `41`, system layouts; a missing reference layout is `XCTFail`, never `XCTSkip`):
  - `deadKeys` is empty for `com.apple.keylayout.PolishPro`, `.RussianWin`, `.Russian`, `.US`, `.ABC`, `.Ukrainian-PC`.
  - `com.apple.keylayout.German` has exactly `{KeyStroke(10,false), KeyStroke(24,false), KeyStroke(24,true)}`; `com.apple.keylayout.French` has exactly `{(33,false), (33,true), (42,false)}`. The values were measured on type 62; if type 41 differs, record the measured set in [research.md R3](./research.md#r3-мёртвые-клавиши) and use it.
  - Existing synthetic `KeyLayout(id:keys:)` calls keep compiling and have empty `deadKeys`.
  - `keys` and `mapping(to:)` results are unchanged (existing tests stay green)
- [X] T008 Add `let deadKeys: Set<KeyStroke>` to `KeyLayout` in `Sources/ReTyper/KeyLayout.swift`:
  - Explicit init `init(id: String, keys: [KeyStroke: Character], deadKeys: Set<KeyStroke> = [])` so existing callers compile.
  - In `KeyLayout.system`, for every key code of `KeyboardKind(keyboardType:).keyCodes` and Shift off/on, call `UCKeyTranslate` a second time with options `0` (dead keys enabled) and `deadKeyState = 0`; a non-zero `deadKeyState` afterwards → insert the stroke into `deadKeys`. The existing `printedCharacter` call with `kUCKeyTranslateNoDeadKeysMask` stays as is, so conversion (feature 002) does not change.
  - Make T007 pass
- [X] T009 [P] Write failing tests in new `Tests/ReTyperTests/TypedFragmentTests.swift` per [data-model.md, TypedFragment](./data-model.md#typedfragment):
  - `append` adds characters in order; `deleteBackward` removes the last one; `deleteBackward` on an empty fragment keeps it empty.
  - `generation` increases on every `append`, `deleteBackward` (including on empty), `reset` and `replaceTail`.
  - `maximumLength == 256`: 256 appends fit; the 257th is not added, `text` becomes empty and `isOverflowed` is set; further `append`/`deleteBackward` keep `text` empty and only bump `generation`; `reset` clears `isOverflowed`.
  - `window` is nil initially and after `reset()`; setting it and then calling `reset()` clears it (use `AXUIElementCreateApplication(getpid())` as a dummy element).
  - `replaceTail(count: 6, with: "привет")` on `ls ghbdtn` gives `ls привет`; `count` greater than `text.count` is a precondition failure, so test only valid counts.
  - `text.count` equals the number of appended characters for Cyrillic and Latin input (one code point each)
- [X] T010 [P] Write failing tests in new `Tests/ReTyperTests/TerminalKeyTests.swift` for `TerminalKey.classify(keyCode:flags:layout:)` per [contract](./contracts/terminal-hotkey.md#terminalkeyclassify), using system layouts `PolishPro`, `RussianWin` and `German` on type `41`:
  - PolishPro: key 5 (`g`) → `.character("g")`; key 5 + Shift → `.character("G")`; key 22 + Shift → `.character("^")`.
  - RussianWin: key 5 → `.character("п")`; key 22 + Shift → `.character(":")`.
  - Space 49 → `.character(" ")`, with Shift too; Backspace 51 → `.backspace`.
  - `.reset` for: Return 36, Keypad Enter 76, Tab 48, Escape 53, Forward Delete 117, arrows 123–126, Home 115, End 119, Page Up 116, Page Down 121, an F-key (122), a keypad digit (83).
  - `.reset` for key 5 and for Backspace with any of `.maskCommand`, `.maskControl`, `.maskAlternate`, `.maskAlphaShift`.
  - `.maskNonCoalesced`, `.maskNumericPad`, `.maskSecondaryFn` alone do not change the result for key 5.
  - German key 24 (dead) → `.reset`; `layout: nil` → `.reset`
- [X] T011 Create `Sources/ReTyper/TerminalReplacement.swift` with the pure types from [data-model.md](./data-model.md):
  - `struct TypedFragment` (`text`, `isOverflowed`, `generation`, `window: AXUIElement?`, `static let maximumLength = 256`, `append`, `deleteBackward`, `reset`, `replaceTail(count:with:)`). Overflow clears `text` (constitution 7.0.0, principles I and III).
  - `enum TerminalKey: Equatable { case character(Character), backspace, reset }` with `static func classify(keyCode: UInt16, flags: CGEventFlags, layout: KeyLayout?) -> TerminalKey` using the constants above; the main-block check uses `layout.keys[KeyStroke(keyCode:shift:)]` so the keyboard kind is already applied.
  - No TIS calls, no logging. Make T009 and T010 pass
- [X] T012 Record typing in `Sources/ReTyper/KeyboardMonitor.swift`:
  - New state: `var recordsTyping = false` (set by AppDelegate), `private(set) var fragment = TypedFragment()`, `func resetFragment()`, and a layout cache `[String: KeyLayout?]` keyed by `"\(id)|\(keyboardType)"` (a nil result is cached too, so a layout without key data costs one lookup).
  - Add `leftMouseDown`, `rightMouseDown`, `otherMouseDown` to the tap mask. In `handle`, a mouse-down calls `resetFragment()` and nothing else: it must **not** call `detector.disarm()` (principle III: mouse input does not cancel the hotkey).
  - On a non-synthetic `keyDown`, after the existing counter and `detector.disarm()`: if `recordsTyping`, read `LayoutManager.shared.currentLayoutID()` and `UInt32(LMGetKbdType())`, get the cached `KeyLayout`, `TerminalKey.classify`, and apply it to `fragment`. When not recording, do nothing with the fragment.
  - When an `append` turns an empty fragment into a non-empty one, schedule `DispatchQueue.main.async` (not inside the tap callback) to read the frontmost app's `AXFocusedWindow` (AX messaging timeout 0.25 s, as in `FocusedText`) and store it in `fragment.window` only if `generation` is still the captured value ([R6](./research.md#r6-прерывание-во-время-замены-fr-009)).
  - On `flagsChanged` with key code 63 or 179 (Fn / Globe): `resetFragment()` ([R2](./research.md#r2-какие-нажатия-пополняют-фрагмент-какие-сбрасывают), dictation).
  - On `tapDisabledByTimeout`/`tapDisabledByUserInput`: `resetFragment()` too (key presses may have been missed).
  - Setting `recordsTyping` to false resets the fragment. Never log characters or key codes
- [X] T013 Wire recording in `Sources/ReTyper/AppDelegate.swift`:
  - `static let typingTerminalBundleIDs: Set<String> = ["com.apple.Terminal"]` next to `terminalBundleIDs`, with a comment that a terminal joins it only after the quickstart scenarios pass in it (constitution 7.0.0, principle III).
  - Observe `NSWorkspace.didActivateApplicationNotification` on `NSWorkspace.shared.notificationCenter`: on every activation `keyboardMonitor.resetFragment()` and `keyboardMonitor.recordsTyping = typingTerminalBundleIDs.contains(bundleID)`. Set the initial value from `NSWorkspace.shared.frontmostApplication` after `keyboardMonitor.start()`. Also observe `NSWorkspace.activeSpaceDidChangeNotification` → `keyboardMonitor.resetFragment()`. Remove both observers in `applicationWillTerminate`, and reset the fragment there.
  - `handleHotkey()` behaviour is unchanged in this task
- [X] T014 Run `swift test`; all tests pass. Build and launch with `./build.sh` (or `swift build`), type in Terminal and check in `~/Library/Caches/com.retyper.app/retyper.log` that nothing typed appears. Confirm the log shows `KeyboardMonitor started` with mouse events added to the tap mask and that macOS showed no new permission prompt (FR-016); if the tap fails to start, stop. Record in `verification.md`

**Checkpoint**: фрагмент набирается и сбрасывается; видимого поведения пока нет

---

## Phase 3: User Story 1 - Исправить только что набранную команду в терминале (Priority: P1) 🎯 MVP

**Goal**: двойной ⌥ в Терминале заменяет набранный фрагмент (или его последнее слово) преобразованным
текстом и переключает раскладку; повторный хоткей возвращает исходный.

**Independent Test**: в Терминале при PL набрать `ghbdtn`, двойной ⌥ → строка `привет`, раскладка RU,
буфер обмена не изменился; Return → оболочка получила `привет`.

### Tests for User Story 1 ⚠️

- [X] T015 [P] [US1] Write failing tests in new `Tests/ReTyperTests/TerminalReplacementTests.swift` for `TerminalReplacement.edit(fragment:onlyLastWord:convert:)` per [contract](./contracts/terminal-hotkey.md#terminalreplacementedit). Use the real converter `{ let r = TextConverter.convert($0, layouts: [polishPro, russianWin], currentLayoutID: <id>); return (r.converted, r.targetLayoutID) }` with system layouts on type `41`:
  - `ghbdtn`, whole line → `TerminalEdit(deleteCount: 6, insert: "привет", targetLayoutID: RussianWin)`.
  - `сгкд -Ш` → `insert "curl -I"`, `deleteCount 7`, target PolishPro.
  - `ghbdtn vbh`, whole line → `привет мир`, `deleteCount 10`.
  - `git commit -m ghbdtn`, `onlyLastWord: true` → `deleteCount 6`, `insert "привет"`.
  - Last word keeps trailing spaces: `ls ghbdtn ` → `deleteCount 7`, `insert "привет "`.
  - `^)` with current PolishPro → `:)`; applying `replaceTail` and calling `edit` again with current RussianWin → `^)` (FR-011 reversibility); same for `ghbdtn` ↔ `привет`.
  - nil for: empty fragment; overflowed fragment; `onlyLastWord` with only spaces; letters tie (`ab аб`); converter returning the same text (`12345` with current `com.apple.keylayout.ABC`); a stub converter whose result length differs from the source
- [X] T016 [P] [US1] Add a `--terminal` mode to `Tools/ReTyperStand/Driver.swift` and pass it through in `Tools/ReTyperStand/run.sh` ([R11](./research.md#r11-автоматическая-сквозная-проверка), [quickstart §4](./quickstart.md#4-автоматический-стенд)):
  - `struct TerminalScenario { number, title, layout, preset, keys (text to type), extraKeys (e.g. Backspace, Left, ⌃A before the hotkey), hotkeyPresses (0, 1 or 2), lastWord, expectedLine, expectedLayout, expectedOutcome }`.
  - Per scenario: select the layout, write the `.command` from «Общие константы», `open -a Terminal`, wait for Terminal frontmost and 1 s for the prompt. Type `keys` by key code: build the reverse map «character → (keyCode, shift)» from `UCKeyTranslate` of the current layout; post without ReTyper's marker so ReTyper sees user input. Post only while Terminal is frontmost; otherwise abort the run.
  - Press double ⌥ with the existing `postOptionTap()`, wait up to 2 s for a `Replacement outcome:` line in the log, press Return, wait up to 3 s for `line-<n>.txt`, compare text, layout and the log outcome. Use `richClipboardContents()` (RTF + text) as the clipboard sentinel and check that it is unchanged (SC-003); check that the log contains none of the typed strings.
  - After a scenario, close its window with ⌘W only if Terminal is frontmost and the focused window's AX title contains the `.command` file name; otherwise leave it and note it in the report.
  - `--repeat N` (default 1) runs every scenario N times; results go to `report.json` like the existing mode. The ordinary mode must give the same scenario 1–11 results (checked in T027).
  - US1 scenarios: T1 PL `ghbdtn` → `привет`, RU; T2 RU `сгкд -Ш` → `curl -I`, PL; T3 PL `ghbdtn`, two hotkeys → `ghbdtn`, PL; T4 preset `ls `, PL `ghbdtn` → `ls привет`; T5 last word on, `git commit -m ghbdtn` → `git commit -m привет`; T6 last word off, `ghbdtn vbh` → `привет мир`; T7 `ghbdtb`, Backspace, `n` → `привет`

### Implementation for User Story 1

- [X] T017 [US1] Add `struct TerminalEdit` and `enum TerminalReplacement { static func edit(...) -> TerminalEdit? }` to `Sources/ReTyper/TerminalReplacement.swift` per the contract: source is `fragment.text` or `ReplacementFlow.lastWord(in:)`; nil for empty/overflowed fragment, empty source, nil target, unchanged result or different length. Make T015 pass
- [X] T018 [P] [US1] Реализовано как `KeyboardMonitor.terminalEvents`: весь массив создаётся заранее, затем отправляется прежнему PID. См. актуальный контракт `implementation.md` вместо прежнего `type`/задержки 1 мс.
- [X] T019 [US1] Add the terminal branch to `handleHotkey()` in `Sources/ReTyper/AppDelegate.swift`:
  - Before the existing terminal check: if the frontmost bundle ID is in `typingTerminalBundleIDs`, call a new `handleTerminalHotkey(app:)`. `terminalBundleIDs` stays the layout-only list for the other terminals; Terminal.app no longer reaches it.
  - In `handleTerminalHotkey`, on the main thread: build `layouts` and `currentLayoutID` exactly as the existing code does; take `fragment` and its `generation` from `keyboardMonitor`; call `TerminalReplacement.edit` with the same `TextConverter` closure and log line `Conversion: source=… len=… target=…`. Nil → `finish(.layoutOnly(reason: "terminal: nothing to convert"))`, fragment unchanged.
  - Otherwise set `isReplacing`, and on `replacementQueue`: `deleteCount` × `KeyboardMonitor.press(keyCode: 51, holdMicroseconds: 1_000)`, then `KeyboardMonitor.type` for each character of `insert`. Back on main: `keyboardMonitor.fragment.replaceTail(count:with:)` (add a mutating method on `KeyboardMonitor` for this), `isReplacing = false`, `finish(.replaced(targetLayoutID:))`.
  - Log `Terminal replacement: len=<deleteCount> target=<id>`; no text. The clipboard is not touched
- [X] T020 [US1] Run `swift test`, rebuild and relaunch ReTyper, run `Tools/ReTyperStand/run.sh --terminal` (scenarios T1–T7) and record per-scenario results in `specs/003-terminal-support/verification.md`

**Checkpoint**: основная замена работает; защитные проверки US2 ещё не добавлены — **не выпускать**

---

## Phase 4: User Story 2 - Никогда не испортить командную строку (Priority: P1)

**Goal**: если ReTyper не уверен в содержимом строки, строка не меняется; защищённый ввод не
запоминается; прерывание обнаруживается.

**Independent Test**: набрать `ghbdtn`, нажать ← (или ⌃A, Tab, щёлкнуть мышью, сменить вкладку),
двойной ⌥ → строка прежняя, раскладка переключилась.

### Tests for User Story 2 ⚠️

- [X] T021 [P] [US2] Сбросы классификатора, очистка/приостановка фрагмента, переполнение и запрет замены покрыты `TerminalReplacementTests.swift`. Последовательности стрелки/Control/Tab/Paste/Mouse/AppReturn/Secure проверены через реальную интеграцию в терминальном стенде вместо дублирования production-switch в тестовом helper.
- [X] T022 [P] [US2] Сценарии реализованы в `TerminalDriver.swift`: T8–T11, T13, Typing0 (заменяет T12), Enter0/10/30/80, TMax, Tab, Paste, Mouse, AppReturn и Secure. См. актуальные критерии в `implementation.md`.

### Implementation for User Story 2

- [X] T023 [US2] Secure input in `Sources/ReTyper/AppDelegate.swift` `handleTerminalHotkey`: first call `IsSecureEventInputEnabled()` (import Carbon); if true → `keyboardMonitor.resetFragment()`, `finish(.layoutOnly(reason: "secure input"))`, nothing typed (FR-007, [R7](./research.md#r7-защищённый-ввод-и-пароли-fr-007))
- [X] T024 [US2] Context check and interruption in `handleTerminalHotkey` ([R6](./research.md#r6-прерывание-во-время-замены-fr-009), FR-009), с одобренным удержанием ввода вместо старого допуска смешивания:
  - On `replacementQueue`, before the first Backspace, check on main that the frontmost PID equals the hotkey app's PID, `keyboardMonitor.fragment.generation` equals the captured value, and the app's current `AXFocusedWindow` is `CFEqual` to `fragment.window`. A mismatch → `finish(.layoutOnly(reason: "context changed"))`; nil window on either side → `finish(.layoutOnly(reason: "window unknown or changed"))`; nothing typed in both cases.
  - Capture `keyboardMonitor.userKeyDownCount` before the series; once started, the series always completes.
  - After the series, on main: if `userKeyDownCount` changed → `resetFragment()`, log `Terminal replacement: interleaved input` (no text), still `finish(.replaced(...))`; otherwise `replaceTail` as in T019
- [X] T025 [US2] Run `swift test` and `Tools/ReTyperStand/run.sh --terminal` (T1–T13); record results in `specs/003-terminal-support/verification.md`

**Checkpoint**: US1 + US2 — выпускаемый объём для Терминала

---

## Phase 5: User Story 3 - Редакторы со встроенным терминалом не затронуты (Priority: P2)

**Goal**: в VS Code, WebStorm и прочих приложениях вне `typingTerminalBundleIDs` поведение как в v0.10.0.

**Independent Test**: сценарии T002 повторяются на новой сборке и совпадают с записанной базовой линией.

### Tests for User Story 3 ⚠️

- [X] T026 [P] [US3] Проверка whitelist: `testOnlyVerifiedStandaloneTerminalIsEnabled` в `TerminalReplacementTests.swift`; источник списка — `TerminalReplacement.supportedBundleIDs`.

### Implementation for User Story 3

- [X] T027 [US3] Run the ordinary stand `Tools/ReTyperStand/run.sh` (scenarios 1–11) on the new build; results must match v0.10.0: no new failures (SC-005, FR-015). Record in `specs/003-terminal-support/verification.md`
- [ ] T028 [US3] Owner repeats the T002 scenarios in Visual Studio Code on the new build (WebStorm: «не проверено», no license — owner decision 2026-09-30), 10 times each (SC-007), and records the comparison with the T002 baseline in `specs/003-terminal-support/verification.md`. Any difference is a defect of this feature

**Checkpoint**: все истории независимо проверены

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: документация и обязательные gates конституции (принцип V, процесс п. 5 и 8)

- [X] T029 [P] README синхронизирован с поддержкой Terminal, сбросами, secure input/read -s и новым удержанием ввода. Старое ограничение про смешивание событий заменено актуальным контрактом. Pending sync снят.
- [X] T030 Build the release candidate as in [quickstart §3](./quickstart.md#3-release-кандидат-принцип-v) (the command list of [feature 002 quickstart §2](../002-symbol-conversion/quickstart.md#2-release-кандидат-по-конституции-принцип-v) without `testPairBuildTime`): full `swift test`; arm64 and x86_64 release builds with `MACOSX_DEPLOYMENT_TARGET=12.0`; `lipo -create` + `lipo -info` = `arm64 x86_64`; `bash scripts/test-package-release.sh`; quit ReTyper, copy into `ReTyper.app`, `codesign --force --sign -`, `codesign --verify --deep --strict --verbose=2`; `open ReTyper.app`. Record each result in `verification.md` (ad-hoc signing locally; CI signs with «ReTyper Dev»). Any failure blocks the rest
- [X] T031 На кандидате: обычный стенд 11/11, терминальный 230/230; T13 min/median/max и границы измерения приведены в verification.md. Полная ручная матрица не подменяется автоматической.
- [ ] T032 Owner runs the manual scenarios 1–16 of [quickstart §5](./quickstart.md#5-ручная-проверка-выполняет-владелец) on the T030 candidate (1–11, 15 and 16 ten times each); a fresh screenshot of Terminal after scenario 1 goes to `specs/003-terminal-support/screenshots/terminal-scenario-1.png`. Record PASS/FAIL/not run per scenario in `verification.md`; scenario 14 (vim) is recorded as observed behaviour, not PASS/FAIL
- [X] T033 Check the **whole** log and caches per [quickstart §6](./quickstart.md#6-журнал) (SC-006, principle I, process item 8): `Terminal replacement:` lines exist; `grep -n -F -e 'ghbdtn' -e 'привет' -e 'сгкд' -e 'curl' ~/Library/Caches/com.retyper.app/retyper.log` and `grep -rl -F 'ghbdtn' ~/Library/Caches/com.retyper.app ~/Library/Preferences/com.retyper.app.plist` find nothing; review any hit manually. Record in `verification.md`
- [X] T034 Отчёт, разрешённый коммит/пуш, CI и публичные артефакты проверены: v0.11.0, ревизия `00b1873`, run 36895863679. Ручные T028/T032 отложены владельцем по release-gate.md. Исторические инструкции ниже применены с актуальным контрактом удержания ввода и конституцией 10.0.0.
  - If T031 or T032 has any FAIL for Terminal.app, remove it from `typingTerminalBundleIDs` before any commit (constitution 7.0.0, principle III: only end-to-end verified terminals).
  - Commit and push only after an explicit request. Suggested: `docs: amend constitution to v7.0.0 (principle III: terminal replacement)` for the constitution and spec files, then `feat: replace typed text in Terminal`. Warn before pushing: a push to `main` starts the release pipeline.
  - Before committing (process item 7): `git config user.name` = `Jarvis`, `git config user.email` = `jarvis.max.dev@proton.me`; otherwise stop and ask. After committing, `git log -1 --format='%an <%ae> | %cn <%ce>'` shows Jarvis for both.
  - After a requested push, wait for CI of that revision (`gh run list --commit <sha>`, `gh run watch <id>`) and record it; the feature is not done until that run succeeds (principle V)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 и T002 — сразу; T003–T005 параллельно; T006 — после них. T002 обязательно до любых изменений кода: это базовая линия v0.10.0.
- **Foundational (Phase 2)**: после T006 = «продолжать». Блокирует все истории.
- **US1 (Phase 3)**: после Phase 2.
- **US2 (Phase 4)**: после US1: T023–T024 правят `handleTerminalHotkey` из T019.
- **US3 (Phase 5)**: после Phase 2 (T026 можно раньше); T027–T028 — на сборке с US1 + US2.
- **Polish (Phase 6)**: после всех историй.

### User Story Dependencies

- **US1**: Phase 2.
- **US2**: US1 (тот же код хоткея). Выпуск только вместе с US1.
- **US3**: не зависит от US1/US2 по коду; проверка имеет смысл на итоговой сборке.

### Within Each User Story

- Тесты (T015, T021, T026) пишутся первыми и падают до реализации.
- `TerminalReplacement.swift` (чистый код) → `KeyboardMonitor` → `AppDelegate` → стенд → запись результатов.
- `Tools/ReTyperStand/Driver.swift` правится в T016 и T022 последовательно.

### Parallel Opportunities

- T003, T004, T005 — разные черновые файлы.
- T007, T009, T010 — разные тестовые файлы; T008 и T011 — разные исходники.
- T015, T016, T018 — разные файлы.
- T021 и T022; T026 — в любой момент после T013.
- T029 — параллельно T030.

---

## Parallel Example: Phase 2

```bash
Task: "Dead-key tests in Tests/ReTyperTests/KeyLayoutTests.swift"        # T007
Task: "TypedFragment tests in Tests/ReTyperTests/TypedFragmentTests.swift"  # T009
Task: "TerminalKey tests in Tests/ReTyperTests/TerminalKeyTests.swift"      # T010
```

## Parallel Example: User Story 1

```bash
Task: "edit() tests in Tests/ReTyperTests/TerminalReplacementTests.swift"  # T015
Task: "--terminal mode in Tools/ReTyperStand/Driver.swift"                  # T016
Task: "KeyboardMonitor.type(_:) in Sources/ReTyper/KeyboardMonitor.swift"   # T018
```

---

## Implementation Strategy

### MVP (US1 + US2)

1. Phase 1: базовая линия и спайки; **стоп**, если S1 или S4 провалены.
2. Phase 2: запоминание набранного.
3. Phase 3 (US1): замена; стенд T1–T7.
4. Phase 4 (US2): защитные проверки; стенд T1–T13.
5. **STOP and VALIDATE**: US1 без US2 не выпускается.

### Incremental Delivery

1. Setup + Foundational → фрагмент записывается, поведение прежнее.
2. + US1 → замена работает на стенде (внутренний checkpoint).
3. + US2 → выпускаемый объём для Терминала.
4. + US3 → подтверждено отсутствие регрессии в редакторах.
5. Polish → README, release-кандидат, ручные сценарии, журнал; коммит и пуш по запросу.
6. Следующие терминалы (iTerm2 и др.) — отдельной задачей: установить, прогнать стенд и ручные сценарии, добавить bundle ID в `typingTerminalBundleIDs`.

---

## Notes

- [P] — разные файлы, нет зависимостей от незавершённых задач.
- Каждая задача с проверкой записывает фактический результат в `verification.md`; невыполненное не отмечается PASS.
- Коммиты — только по явному запросу владельца; до этого все изменения остаются в рабочей копии `main`.
- Во время прогонов стенда ничего не печатать и не трогать мышь (около минуты на режим, дольше с `--repeat 10`).
