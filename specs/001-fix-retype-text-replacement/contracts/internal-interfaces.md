# Внутренние интерфейсы компонентов

**Актуализировано**: 2026-09-09 | **Модель**: [data-model.md](../data-model.md)

Внешнего API у фичи нет. Ниже существующие интерфейсы из `Sources/ReTyper/` и контракт релизного скрипта, а не предлагаемые протоколы. Прежние `ReplacementCoordinating`, `ReplacementFeedback`, `ClipboardBackup`, `ReplacementRequest` и расширение событий с `syntheticMarker` не описывают текущий код.

## Доступ к тексту

Определён в `ReplacementModels.swift`, реализован `AccessibilityTextClient`:

```swift
protocol TextAccessProviding {
    func captureCapability(applicationPID: pid_t, activationPID: pid_t,
                           deadline: TimeInterval) throws -> TextAccessCapability
    func isFocused(_ target: TextAccessCapability, deadline: TimeInterval) throws -> Bool
    func snapshot(_ target: TextAccessCapability, deadline: TimeInterval) throws -> TextSnapshot
    func selectRange(_ range: Range<Int>, in target: TextAccessCapability, deadline: TimeInterval) throws
}
```

- `deadline` является абсолютным монотонным сроком по `systemUptime`, не числом пауз. Клиент ограничивает AX messaging timeout оставшимся бюджетом и 100 мс, проверяет срок после запросов.
- `applicationPID` является проверенным получателем сопоставленного завершающего `flagsChanged` хоткея из `.cgAnnotatedSessionEventTap`, а `activationPID` отдельно фиксирует активное приложение. Оба должны быть положительными. AX-дерево читается у `applicationPID`, не у свидетеля активации; подстановки `NSWorkspace` вместо отсутствующего получателя нет.
- Клиент проверяет живой `NSWorkspace.shared.frontmostApplication` относительно `activationPID` при захвате и до/после чтений фокуса. `isFocused` требует совпадения `kAXFocusedUIElementAttribute` с сохранённым элементом и совпадения его окна через сохранённый источник. При `applicationPID != activationPID` нужен фактический `CFBoolean true` в `AXFocused` именно сопоставленного поля; отсутствие, неверный тип (включая число вместо boolean) или `false` дают отказ. При равных PID этот дополнительный атрибут не нужен для `.field`, но обязателен для `.application` в `resolveWindow`.
- `resolveWindow` при захвате предпочитает прямой `AXWindow` поля (`TextWindowSource.field`). Только его отсутствие допускает `AXFocusedWindow` того же приложения (`.application`): положительный `applicationPID == activationPID == текущий активный PID`, фактический `CFBoolean true` в `AXFocused` поля, корректный AX-элемент окна с ролью `AXWindow` и PID владельцев **поля и окна**, равные `applicationPID`. Дополнительные проверки роли окна и владельцев относятся только к резервному пути; прямой путь сохранён. Присутствующий неверный тип и реальные ошибки чтения не разрешают fallback. Capability сохраняет `let windowSource: TextWindowSource`; повторный вызов использует только этот источник и сверяет прежние поле/окно, без подмены источника при его потере или ошибке.
- Допустимы `AXTextField`, `AXTextArea`, `AXComboBox` и not secure; `acceptsEnabled(_:role:)` принимает присутствующий `AXEnabled` только как фактический `CFBoolean true`, отсутствие только для `AXTextArea`. `false`, неверные типы и реальные ошибки не считаются отсутствием. `supportsReplacement` по-прежнему требует writable value и selection range. Неактивирующая панель не освобождается от этих условий или проверки полного значения и диапазона; специальных списков приложений и приватных API определения получателя нет.
- `AccessibilityTextClient.acceptsSubrole(_ value: CFTypeRef?) -> Bool` получает исходный результат `optionalAttribute` до допуска, не результат предварительного `as? String`. `nil` даёт `true`; присутствующая нестрока или `kAXSecureTextFieldSubrole` дают `false`, и capture выбрасывает `TextAccessError.unavailable`. `.noValue`/`.attributeUnsupported` допускают отсутствие, прочие ошибки чтения не скрываются. Признак не сохраняется отдельным полем capability и не заменяет остальные проверки.
- `TextAccessCapability.acceptsActivation(_ currentPID: pid_t?, fieldFocused: Bool?)` объединяет проверку положительных PID, неизменного свидетеля и дополнительного фокуса панели. Свидетель активации не является независимым запросом фактической клавиатурной цели; результат helper не подтверждает приём текста приложением.
- `AXManualAccessibility` запрашивается точечно; успешный запрос кешируется по PID и дате запуска. Временная ошибка не кешируется как успех; запрос не доказывает готовность дерева.
- CF-типы, точные UTF-16-диапазоны и соответствие `selectedText` проверяются. Два последовательных снимка должны совпасть по полному значению и диапазону; это не транзакционная гарантия AX.
- `selectRange` записывает только `AXSelectedTextRange`, не текст. Успешный системный ответ требует отдельного подтверждения координатором; `AXValue` и `AXSelectedText` для записи текста не используются.
- Ошибки различаются через `TextAccessError`; отказ не включает терминальный или иной разрушительный fallback. `waitUntil` в этом протоколе отсутствует: цикл наблюдения находится в координаторе.

Локальные зависимости `copyAttribute` и `frontmost` в `AccessibilityTextClient` позволяют изолированно подменить чтение атрибутов и активный PID в unit-тестах. Это точки подмены реализации, не изменение `TextAccessProviding` или транспортного `ReplacementInputProviding`. Результаты и ограничения проверок нового оконного пути ведутся в [verification.md](../verification.md#совместимость-ax-2026-09-08-и-2026-09-09).

## Подготовка и передача ввода

Определён в `ReplacementModels.swift`, реализован `KeyboardMonitor` через `SyntheticInputGate`:

```swift
protocol ReplacementInputProviding {
    var activityGeneration: UInt64 { get }
    func prepare(_ text: String, targetPID: pid_t, activationPID: pid_t,
                 generation: UInt64, deadline: TimeInterval) -> PreparedTextInput?
    func send(_ input: PreparedTextInput)
    func delivery(of input: PreparedTextInput) -> InputDelivery
    @discardableResult func cancel(_ input: PreparedTextInput) -> InputDelivery
    func finish(_ input: PreparedTextInput)
}
```

- `prepare` не отправляет события. `SyntheticTextPayload.make` создаёт одну пару Unicode key-down/key-up с пустыми флагами и без autorepeat; проверяет точное локальное чтение обратно обоих событий. Предел 4096 единиц UTF-16 не обещает приём любой меньшей строки платформой. При отказе возвращается `nil`, без дробления и без изменений поля.
- `targetPID` равен захваченному `applicationPID`; `activationPID` хранится отдельно в билете. `prepare` требует положительные оба PID, конечный будущий дедлайн и живой свидетель `frontmostPID() == activationPID` до и после создания событий, затем проверяет доступность шлюза, поколение и ёмкость. Переданный провайдер `frontmostPID` читает `NSWorkspace`, а не кеш уведомления и не фактическую клавиатурную цель.
- `send` однократно ставит инертные `.null`-сигналы **в `.cgSessionEventTap`**. Активный session-перехватчик через шлюз разрешает направление подготовленного ввода через `postToPid` сохранённому `targetPID`; прохождение `.null` до annotated tap не требуется. Annotated-перехватчик подписан только на `flagsChanged` и не фильтрует process-targeted Unicode-эхо.
- `eventTargetUnixProcessID` у `.null` (`null.targetPID` в диагностике) не является клавиатурным свидетельством. `SyntheticInputGate.handle(type:token:)` не принимает и не проверяет это поле; адресат берётся из билета, а допускающие проверки используют живой свидетель активации, поколение и дедлайн.
- `takeSignals`, обработка down-сигнала и `delivery` повторно проверяют доступность шлюза, текущую активацию относительно `activationPID`, поколение и дедлайн. `KeyboardMonitor.prepare`, `send` и `delivery` требуют живой готовности **обоих** перехватчиков; перед обработкой стадии она проверяется также по обоим текущим handles. Пользовательские события учитываются на ранней session-стадии, уведомления об активации также меняют поколение; собственные токены не учитываются как пользовательский набор. Проверка активации дополняет поколение, но не является независимым текущим запросом получателя клавиатуры.
- `queued` допускает отмену. `handedOff` означает прохождение локальной точки передачи, **не ACK приложения и не подтверждение конкретного поля**. `cancel` после передачи не может доказать недоставку.
- Поздние, повторные и выведенные из обращения токены не отправляют текст снова. Парный key-up для переданного key-down направляется тому же PID, даже если контекст уже изменился. Это завершение пары, не повтор операции.
- `finish` освобождает квитанцию, оставляя при необходимости только ограниченное состояние ожидающего key-up. После завершения её срока жизни отсутствие квитанции не доказывает отмену.
- Ни одного обращения к буферу обмена и ни одного внутреннего буфера набранного текста в этом контракте нет.

### Стадии одного монитора

Оба перехватчика создаются как активные `.defaultTap` в одном `KeyboardMonitor` и обслуживаются основным run loop. Это не два монитора и не два независимых распознавания хоткея.

| Стадия `KeyboardEventStages.Stage` | Подписка и ответственность |
|----------------------------------|----------------------------|
| `session` | `.cgSessionEventTap`: `.null`, клавиши, модификаторы, мышь и прокрутка. Собственные токены передаются `SyntheticInputGate.handle(type:token:)`; повторно встроенные собственные non-null события отбрасываются, новые пользовательские события сразу увеличивают поколение |
| `annotated` | `.cgAnnotatedSessionEventTap`: **только `flagsChanged`**. Сопоставляет событие с session-стадией, распознаёт хоткей и читает реальный `eventTargetUnixProcessID`; не вызывает транспортный фильтр для Unicode-эха `postToPid` и не учитывает его как новую активность |

- `@discardableResult func recordActivity() -> UInt64` увеличивает и возвращает поколение под одной блокировкой шлюза. Session-стадия сохраняет **этот** результат вместе с одним отпечатком модификатора `(timestamp, keyCode, sourceUserData)`, а не получает поколение отдельным последующим чтением.
- Annotated-стадия требует готовности обоих перехватчиков, точного совпадения всех частей отпечатка, `observed.generation == gate.activityGeneration` и `observed.generation < UInt64.max`. Успешное сопоставление потребляет отпечаток; несовпадение, промежуточная активность или нарушение порядка сбрасывает готовность хоткея. Повторного увеличения поколения на annotated-стадии нет. `KeyboardEventStages.Decision.hotkey(pid_t?, UInt64, TimeInterval)` возвращает результат `checkedPID(_:)` для получателя завершающего события, именно `observed.generation` и переданный `now` по `systemUptime`. Новое чтение поколения для результата не выполняется; timestamp отпечатка и время решения имеют разные назначения.
- `KeyboardEventStages.modifierEvent` хранит только одну необязательную запись и поколение. Не удерживаются сам `CGEvent`, Unicode-содержимое или история обычных клавиш; агрегированное состояние жеста остаётся в `ModifierHotkeyDetector`.
- При выключении любого tap допуск шлюза и состояние жеста сбрасываются. Переход в готовность требует обоих включённых tap; необходимый key-up уже переданного key-down допускается и после потери готовности. `start()` создаёт оба tap и оба run-loop source, при неполной инициализации освобождает созданные tap; `stop()` отключает и освобождает оба, удаляет источники и наблюдателя активации. При timeout/user-input disable обрабатывается конкретный tap, но готовность после включения снова определяется по обоим.
- Историческое основание разделения стадий: [проба key-up в собственный PID](../research.md#основания-и-границы-свидетельств) показала annotated-эхо, которое промежуточный единственный annotated-шлюз отбрасывал по правилу фильтрации собственных non-null событий. Теперь это правило действует только при повторном встраивании в session-поток; annotated-путь не блокирует нормальную доставку пары. Текущие проверки: [verification.md](../verification.md#текущий-статус).

## Вычисление фрагмента

`TextFragmentResolver` предоставляет существующие статические функции:

```swift
static func isValid(_ snapshot: TextSnapshot) -> Bool
static func fragmentFromSelection(_ snapshot: TextSnapshot) -> ReplacementFragment?
static func fragmentBeforeCaret(_ snapshot: TextSnapshot) -> ReplacementFragment?
static func fragmentFromLineStart(_ snapshot: TextSnapshot) -> ReplacementFragment?
static func expectedValue(after fragment: ReplacementFragment,
                          replacedWith text: String, in snapshot: TextSnapshot) -> String?
static func expectedValueAfterDeletion(of fragment: ReplacementFragment,
                                     in snapshot: TextSnapshot) -> String?
```

Это перечень сигнатур, не новый протокол. Последняя функция остаётся чистым вычислением и **не используется как разрешение отдельного удаления** в текущем пути замены.

Позиции выражены в UTF-16; неверные координаты, переполнение, разрыв расширенной графемы или несовпадение текста дают `false`/`nil` без подрезки или расширения диапазона. Проверяется точное равенство UTF-16, не каноническая эквивалентность. Без выделения режим слова ограничен пробелом, табуляцией, LF/CR; режим строки сохраняет пробелы и табуляцию до курсора, ограничен LF/CR. При пустом фрагменте возвращается `nil`.

## Конвертация и ручной выбор

`CharacterMap.cyrillicLayout(for layoutID: String) -> CyrillicLayout?` использует точный `CyrillicLayout(rawValue:)`, без `contains`. `isLatinLayout(_ layoutID: String) -> Bool` принимает закрытый список известных полных ID для ручной группировки; существующий `isEnglishLayout(_:)` делегирует ему. Отдельный `isSupportedLatinTarget(_ layoutID: String) -> Bool` допускает только `com.apple.keylayout.US`, `com.apple.keylayout.ABC`, `com.apple.keylayout.PolishPro`. Полный список и соответствия enum: [модель](../data-model.md#идентификаторы-раскладок).

`TextConverter.autoConvert(_ text: String, availableLayoutIDs: [String]) -> (converted: String, targetLayoutID: String?)` сохраняет порядок переданного списка. Для кириллицы выбираются первая известная кириллическая таблица и первая совместимая латинская цель; без такой пары возвращается `(text, nil)`, не преобразованный текст с несовместимой целью. Для латинского текста остаётся первая известная кириллическая цель. `LayoutManager.relevantLayoutIDs()` не сужает сохранённый ручной выбор до автоматических целей и не перезаписывает настройки.

Обратный белорусский словарь после построения из прямого получает явное `map["'"] = "]"`. Прямые `]`/`}` -> `'` не меняются; канонический inverse согласован владельцем, не выводится из порядка словаря или неизвестного Shift. Таблицы не расширены.

## Координатор

Существующий `final class TextReplacementCoordinator` принимает `TextAccessProviding`, `ReplacementInputProviding`, подменяемые часы, паузу и конвертацию. Основные точки входа:

```swift
func performReplacement(_ options: ReplacementOptions) -> ReplacementResult
var recoveryOriginalText: String? { get }
@discardableResult func clearRecovery() -> Bool
```

- `performReplacement` синхронен для вызывающего фонового потока. Сам координатор не владеет интерфейсом, раскладкой или буфером обмена. Защищает `busy` и сохранённый исходник блокировкой; повторный вход даёт `aborted(.busy)`, незавершённое ручное восстановление даёт `aborted(.recoveryPending)`.
- До `captureCapability` проверяются положительные `applicationPID`/`activationPID`, конечный `triggeredAt`, `0 <= startedAt - triggeredAt < 0.3` и неизменное поколение. Метка из будущего, возраст 300 мс и более, неверные PID или смена поколения после решения хоткея дают `aborted(.contextChanged)` без захвата. `triggeredAt` использует `systemUptime` решения хоткея и не обновляется ни в делегате, ни при запуске фоновой задачи. Начальный абсолютный дедлайн **`captureDeadline = options.triggeredAt + 0.3`** общий для времени после решения, включая dispatch, capability и исходный снимок: новые 300 мс после dispatch не выдаются. Истечение срока проверяется между capability и снимком и после снимка; поздний исходный снимок не разрешает подготовку ввода.
- Координатор передаёт оба PID в `captureCapability` и сверяет оба в возвращённом capability с options. Обычная замена и единственная допустимая попытка восстановления передают `applicationPID` как `targetPID` и тот же `activationPID` в `prepare`.
- Ввод готовится до установки диапазона. Перед отправкой заново проверяются привязка к получателю, живой свидетель активации, неизменный источник окна и его условия, то же окно, AX-элемент, строгий фокус неактивирующего поля либо источника `.application`, поколение, полный исходный текст и точный диапазон, включая уже существующее выделение пользователя. Потеря источника не разрешает переключение на другой путь; после `handedOff` неподтверждённый контекст требует ручного восстановления без нового слепого ввода.
- После начального захвата последующие этапы подтверждения получают собственные монотонные бюджеты 300 мс с повторными проверками после чтений; это не продлевает начальный дедлайн задним числом. Успех требует полного ожидаемого значения, пустого выделения и курсора после фрагмента. Свежий поздний полностью корректный результат в завершающей проверке операции возвращает `replaced` без отката; после возврата `needsRecovery` фонового наблюдения и автоматического снятия блокировки нет.
- После отмены queued-события возможно условное восстановление только выделения при исходном тексте и прежнем контексте. Смена контекста не разрешает воздействие на другое поле.
- После `handedOff` частичный, отсутствующий или конфликтующий результат не разрешает второй ввод. Исходник остаётся в памяти, исход `needsRecovery` блокирует новые операции.
- Только наблюдаемое полное преобразованное значение с неверным курсором разрешает одну адресную попытку восстановления известного диапазона. Полное исходное значение и курсор проверяются; неудача оставляет ручное восстановление, без повторов.
- `clearRecovery()` не вводит текст, не трогает буфер обмена и возвращает `false` во время `busy`. Предупреждение и явное согласие пользователя обеспечивает вызывающий UI, не этот метод.

## Связь с интерфейсом

`KeyboardMonitor.onHotkeyTriggered: ((pid_t?, UInt64, TimeInterval) -> Void)?` вызывается после сопоставления единственного отпечатка и его точного поколения между session- и annotated-стадиями. Он передаёт все три значения из `Decision.hotkey`: результат `checkedPID(_:)` для `eventTargetUnixProcessID` завершающего `flagsChanged` в `.cgAnnotatedSessionEventTap`, сопоставленное поколение и монотонное время решения. Преобразование принимает только положительный точно представимый `pid_t`; невалидное значение даёт `nil`, а не усечение или резервный PID из session-метаданных/`NSWorkspace`.

Сигнатура обработчика делегата: `private func handleHotkey(applicationPID: pid_t?, generation: UInt64, triggeredAt: TimeInterval)`. На основном потоке он проверяет занятость и отдельно получает свидетель `activationPID`. Отсутствующий получатель или свидетель дают `aborted(.noTextAccess)`, а при доступном исходнике для восстановления `aborted(.recoveryPending)`, без запуска координатора и fallback-получателя. Ранняя ветка вызывает общий `applyLayoutSwitch`, затем `signalOutcome`. Иначе делегат резервирует `replacementRunning`, получает настройки и формирует `ReplacementOptions` **до** фоновой задачи. `inputGeneration: generation` и `triggeredAt: triggeredAt` передаются напрямую, без чтения текущего поколения или часов для замены исходных значений. Поэтому активность после решения до обработки не становится допустимым новым поколением.

### Переключение раскладки

Существующие определения в `ReplacementModels.swift`:

```swift
enum LayoutSwitchAction: Equatable {
    case next
    case select(String)
}

// ReplacementResult
func layoutSwitchAction(activationPID: pid_t?, currentActivationPID: pid_t?,
                        inputGeneration: UInt64, currentInputGeneration: UInt64) -> LayoutSwitchAction?
```

Метод чистый: положительный `activationPID`, равенство с `currentActivationPID` и равенство поколений обязательны для любого действия. `replaced` с `targetLayoutID` даёт `.select`, без цели `nil`; `layoutOnly` и обычный `aborted` дают `.next`. `busy`, `contextChanged`, `recoveryPending`, `needsRecovery`, `restoredAfterFailure` дают `nil`, даже с целью. Получатель и часы в политику не передаются.

`private func applyLayoutSwitch(_ result: ReplacementResult, activationPID: pid_t?, generation: UInt64)` в `AppDelegate` читает текущие активацию/поколение только для сравнения и выполняет `LayoutManager.switchToNextLayout()` или `switchTo(layoutID:)`. Его вызывают **обе** ветки: ранний отказ и нормальное завершение координатора с `options.activationPID`/`options.inputGeneration`. Ранний `recoveryPending` подавляет переключение; отсутствие получателя не разрешает текстовую операцию, но обычный отказ может дать `.next` при достоверном неизменном свидетеле. Эти чтения не обновляют исходные options или время хоткея. Возвращённое действие не подтверждает успешность системного переключения.

### Сигнал и сообщение

Существующие точки доступа `StatusBarFeedbackState` из `StatusBarFeedbackState.swift`:

```swift
mutating func recordOutcome(_ outcome: ReplacementOutcome)
var outcomeMessage: String? { get }
mutating func flashFailure(at uptime: Double)
func showsWarning(at uptime: Double) -> Bool
```

Это перечень сигнатур, не новый протокол. Приватный `lastFailure: ReplacementOutcome?` хранится отдельно от `failureFlashDeadline`; `outcomeMessage` вычисляется, причём `isRecoveryAvailable` имеет приоритет. `recordOutcome(_:)` сохраняет неуспех без запуска сигнала; `replaced` / `layoutOnly` очищают причину и дедлайн, а `aborted(.busy)` оставляет их неизменными. Переход `isRecoveryAvailable` из `true` в `false` через `didSet` очищает причину, но не активный краткий сигнал; повторное `false` обычную причину не стирает. Полная модель переходов: [data-model.md](../data-model.md#состояние-обратной-связи).

После завершения координатора `AppDelegate` синхронизирует доступность восстановления, затем передаёт исход через `StatusBarController.recordOutcome(_:)`; ранняя ветка сигнализирует отказ, не меняя уже существующее состояние recovery. Для неуспеха отдельно вызывается `flashFailure()`, а `busy` игнорируется. `StatusBarController.recordOutcome(_:)` обновляет состояние, передаёт вычисленное сообщение в `PopoverViewController.showOutcomeMessage(_:)` и обновляет индикатор. `showRecovery(_:)` синхронизирует признак состояния, доступность действий панели и сообщение, не передавая исходный текст.

`StatusBarController.updateTitle()` независимо выбирает краткий/постоянный символ предупреждения и описание для `button.toolTip` и метки доступности. Объяснение обычного отказа остаётся в панели и подсказке после 1,5 секунды, хотя индикатор снова показывает раскладку; без восстановления успешный исход очищает и сообщение, и краткий сигнал. Таймер вызывает только `updateTitle()`: чтение текущего состояния, смена раскладки и старые таймеры не стирают причину или более новый сигнал.

### Содержимое и размер панели

Существующие интерфейсы `PopoverViewController` из `PopoverViewController.swift`:

```swift
func showRecovery(_ isAvailable: Bool)
func showOutcomeMessage(_ message: String?)
var onContentSizeChanged: ((NSSize) -> Void)?
```

- `showRecovery(_:)` и `showOutcomeMessage(_:)` сохраняют переданное состояние, не загружая view заранее. Одинаковое значение не вызывает перестроения; изменившееся перестраивает только уже загруженный view. `nil` убирает секцию сообщения, а не доступность восстановления.
- Сообщение показано отдельной многострочной секцией под разрешениями. Действия `Copy Original Text` / `Clear Recovery` добавляются только при доступном восстановлении, не из-за наличия обычного объяснения отказа.
- После построения вычисляется `NSSize(width: 340, height: ceil(stack.fittingSize.height))` и записывается в `preferredContentSize`. При установленном `onContentSizeChanged` размер передаётся владельцу через callback; уже размещённый view (`view.superview != nil`) не меняет собственный frame.
- До размещения (`view.superview == nil`) начальный размер задаётся через `view.setFrameSize(size)` перед callback, без сброса origin. Без callback контроллер сам задаёт размер этим же методом; это отдельная ветка, не второй владелец размера в рабочей связке с панелью.
- `StatusBarController` устанавливает callback с обновлением `NSPopover.contentSize`. Непосредственно перед показом он лениво загружает `popoverVC.view`, устанавливает `popover.contentSize = popoverVC.preferredContentSize` и только затем вызывает `popover.show(...)`. Поэтому сообщение, полученное до первого открытия, участвует в начальном размере; загрузка не переносится в инициализацию до старта монитора.

### Действия восстановления

`onCopyOriginal` обрабатывается в `AppDelegate`: это **единственная** запись в `NSPasteboard.general`, только после нажатия `Copy Original Text`. Она заменяет текущее содержимое буфера; ошибка записи даёт сигнал и не очищает исходник. `onClearRecovery` вызывается после предупреждения и явного подтверждения `Clear Recovery`; копирование не снимает блокировку автоматически. Выход возвращает `terminateLater` при работающей операции и предупреждает, если сохранён исходник. Завершение процесса не сохраняет его на диск.

## Релизная упаковка

Контракт `scripts/package-release.sh`: четыре позиционных аргумента `VERSION SOURCE_APP OUTPUT_DIR IDENTITY`. `.releaserc` вызывает его на стадии prepare через [@semantic-release/exec](https://github.com/semantic-release/exec):

```bash
bash scripts/package-release.sh "${nextRelease.version}" ReTyper.app . "ReTyper Dev"
```

`${nextRelease.version}` подставляет [semantic-release](https://github.com/semantic-release/semantic-release), это не самостоятельная shell-переменная. Каталог результата должен существовать вне исходного `.app`; источник не изменяется. Скрипт создаёт собственный staging, копирует bundle, задаёт `CFBundleShortVersionString` и `CFBundleVersion`, затем выполняет окончательную подпись. DMG и ZIP строятся из одного подписанного staging-приложения, не из двух независимо изменяемых копий.

До установки архивов проверяются staging, приложение в read-only смонтированном DMG и извлечённый ZIP: обе версии, наличие arm64/x86_64, `codesign --verify --deep --strict --all-architectures`, точное содержимое относительно staging и соответствие его симлинков. После проверок архивы перемещаются в `OUTPUT_DIR`; `.version` записывается последним и означает только успешную подготовку, не публикацию. Ошибка после снятия прежнего маркера не должна оставлять новый маркер успеха; очистка ограничена собственным staging/монтированием. Это не гарантия атомарной публикации пары файлов или отзыва уже опубликованного релиза.

`scripts/test-package-release.sh` использует только собственный временный универсальный C-bundle с ad-hoc identity `-`, реальные архивы и локальную подмену `hdiutil` для инъекции сбоев. Он не запускает ReTyper и не использует production identity. Протокол и пределы: [quickstart.md](../quickstart.md#изолированная-проверка-упаковки); локальные результаты основного исполнителя и агента: [verification.md](../verification.md#текущий-статус). Оба тестовых шага обязательны в `build` до сертификатов; `release` имеет `needs: build`. Полный release-bundle и удалённый прогон остаются отдельными T056/T036 и T057/T040.

## Диагностика и проверяемость

`Logger.log(_:)` принимает только метаданные по контракту вызывающих участков; произвольную строку нельзя надёжно автоматически обезличить. `~/Library/Caches/com.retyper.app/retyper.log` ограничен 1 MiB, каталог `0700`, файл `0600`. Запись асинхронна, очередь ограничена; при перегрузке новые сообщения могут отбрасываться. Полные снимки, фрагменты, clipboard и последовательность нажатий не журналируются.

`SettingsManager.loginItemFailureMessage(_ error: Error, legacy: Bool) -> String` формирует `Login item update failed (backend=SMAppService, code=<число>)` либо фиксированный backend `LaunchAgent` при `legacy == true`; число берётся из `(error as NSError).code`. Оба catch используют helper, не raw error, `localizedDescription`, domain, userInfo или путь. Успешное создание пишет только `LaunchAgent created`. `LoggerTests.testLoginItemFailuresLogOnlyBackendAndNumericCode` пропускает синтетическую ошибку с чувствительными маркерами через helper в отдельный временный `Logger(fileURL:)`, не переключая автозапуск и не читая пользовательский журнал.

Единственный источник текущих результатов, количества тестов и датированных прогонов: [verification.md](../verification.md#текущий-статус). Здесь описано существующее покрытие, не результат нового запуска. Координатор проверяется с подменой доступа, ввода и времени. Тесты шлюза не отправляют клавиатурный ввод; тесты логгера читают только собственные временные файлы. `StatusBarFeedbackStateTests` проверяют независимый срок сигнала, сохранение объяснения после него и при `busy`, очистку успехом и переходом из восстановления.

`AccessibilityTextClientTests` проверяет чистый допуск `nil`/обычной строки и отказ secure-строке, boolean, числу, массиву и словарю; реальный AX-захват этим не покрывается. `LayoutSwitchPolicyTests` проверяет `.next`/`.select`, отсутствие цели, защищённые исходы и отсутствующий/невалидный/изменённый контекст; весь делегат и системная смена раскладки не вызываются. Связка обоих вызовов `applyLayoutSwitch` дополнительно сверяется по исходникам. `CharacterMapTests`/`TextConverterTests` покрывают точные ID, PC-пунктуацию в обоих направлениях, отказ несовместимым латинским целям, порядок совместимых целей и канонический белорусский inverse. Это изолированное покрытие корректирующей части Convergence: T044-T050/T059 реализованы, но ручные T051-T058/T060-T063 и их исходные задачи этим не закрываются.

`KeyboardMonitorPIDTests` проверяет допустимость PID без усечения; `KeyboardEventStagesTests` проверяет сопоставление стадий, отсутствие fallback, раннее поколение, готовность обоих tap и пропуск annotated-эха без повторной маршрутизации. `TextAccessCapabilityTests` проверяет отдельный свидетель и обязательный положительный фокус при разных PID. `TextReplacementCoordinatorTests.testActivityAfterHotkeyDecisionAbortsBeforeCapabilityCapture` получает настоящее решение чистой модели стадий, затем увеличивает поколение и передаёт исходные значения в options: ожидаются `contextChanged`, отсутствие capability/снимков/выделений/ввода и неизменное поле подмены. Это не вызов делегата и не живая замена; прямую передачу в `AppDelegate` дополнительно сверяют по коду. Свежий запуск и проверки начального дедлайна/жизненных циклов учитываются в открытой T042 по [quickstart.md](../quickstart.md#изолированная-проверка-получателя-и-p2).

`Tests/ReTyperTests/PopoverLayoutTests.swift` проверяет сохранение origin при сообщении отказа, восстановлении и очистке; повторное перестроение без накопления секций, с видимыми крайними строками и возвратом к исходной высоте; синхронизацию `NSPopover.contentSize` через callback; корректный начальный размер при сообщении до первого показа. Эти проверки не заменяют визуальную приёмку рабочего приложения.

Модульные тесты, инертные сигналы и изолированный стенд не доказывают семантику конкретного внешнего поля и не заменяют живую приёмку из [quickstart.md](../quickstart.md). Подтверждения пользователем базовых сценариев OpenChamber и компоновки были получены до изменений Spotlight/P2 и не означают прохождения новых живых, визуальных или релизных проверок; их статус учитывается в [verification.md](../verification.md#текущий-статус).

Полная живая замена в [Spotlight](https://support.apple.com/guide/mac-help/search-with-spotlight-mchlp1008/mac) учитывается ручной частью T042 и требует явно согласованного безопасного сеанса по [сценарию 11](../quickstart.md#сценарий-11-реальный-spotlight). Контролируемые метаданные получателя не подтверждают замену запроса, а доставка с ожидаемым текстом и курсором в собственное неактивирующее поле подтверждает только стенд, не Spotlight. Для произвольной неактивирующей панели неизменная активация может пережить закрытие/смену панели; чтение AX не является независимым свидетельством текущего получателя клавиатуры. Общий допуск не гарантирует поддержку всех таких полей. При отсутствии подтверждения до передачи выполняется отказ, при неизвестном результате после `handedOff` сохраняется ручное восстановление, без слепого повтора.

Официальные интерфейсы: [Apple AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement), [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent), [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace), [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard), [NSPopover](https://developer.apple.com/documentation/appkit/nspopover), [NSViewController](https://developer.apple.com/documentation/appkit/nsviewcontroller), [XCTest](https://developer.apple.com/documentation/xctest), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html), [подпись кода Apple](https://developer.apple.com/library/archive/technotes/tn2206/_index.html), [Bash](https://www.gnu.org/software/bash/).
