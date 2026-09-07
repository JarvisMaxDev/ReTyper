# ReTyper

<p align="center">
  <strong>macOS keyboard layout switcher</strong><br>
  Instantly convert mistyped text between Latin and Cyrillic layouts
</p>

<p align="center">
  <a href="https://github.com/JarvisMaxDev/ReTyper/releases/latest">
    <img src="https://img.shields.io/github/v/release/JarvisMaxDev/ReTyper?style=flat-square&label=Download&color=brightgreen" alt="Download latest release">
  </a>
  <img src="https://img.shields.io/badge/platform-macOS%2012%2B-blue?style=flat-square" alt="macOS 12+">
  <img src="https://img.shields.io/badge/arch-Universal%20(ARM64%20%2B%20x86__64)-orange?style=flat-square" alt="Universal Binary">
</p>

---

## What is ReTyper?

Ever typed a whole sentence only to realize you were in the wrong keyboard layout?

```
ghbdtn vbh  →  привет мир
```

**ReTyper** sits in your menu bar and converts already-typed text between Latin and Cyrillic with a single hotkey. No need to retype — just press **double ⌥** and it fixes everything in place.

## Features

- 🔄 **Instant conversion** — select text or let ReTyper auto-select, then convert with a hotkey
- ⌨️ **Configurable hotkey** — double-tap any modifier (⌥/⇧/⌃/⌘)
- 🔤 **Word or line mode** — convert only the last word or everything to start of line
- 🌍 **Multiple layouts** — choose which Latin + Cyrillic layouts to switch between
- 🔊 **Sound feedback** — optional click sound on switch
- 🚀 **Autostart** — launch at login

## Supported Layouts

| Layout           | Script   | Mapping             |
| ---------------- | -------- | ------------------- |
| English (QWERTY) | Latin    | Base QWERTY         |
| Polish Pro       | Latin    | Extended Latin      |
| Russian (ЙЦУКЕН) | Cyrillic | Standard Apple      |
| Russian (PC)     | Cyrillic | Windows-style       |
| Ukrainian        | Cyrillic | ЙЦУКЕН + ґ, є, і, ї |
| Ukrainian (PC)   | Cyrillic | Windows-style UA    |
| Belarusian       | Cyrillic | ЙЦУКЕН + ў, і       |

## System Requirements

| Requirement      | Minimum                             |
| ---------------- | ----------------------------------- |
| **macOS**        | 12.0 (Monterey) or later            |
| **Architecture** | Apple Silicon (M1+) or Intel x86_64 |
| **Disk space**   | ~5 MB                               |
| **RAM**          | Negligible (~10 MB at runtime)      |
| **Permissions**  | Accessibility + Input Monitoring    |

---

## Installation

### Homebrew (recommended)

```bash
brew tap JarvisMaxDev/tap
brew install --cask retyper
```

### Download DMG

1. Go to [**Releases**](https://github.com/JarvisMaxDev/ReTyper/releases/latest)
2. Download `ReTyper-macOS-universal.dmg`
3. Open the DMG and drag **ReTyper** to Applications

### Build from source

```bash
git clone https://github.com/JarvisMaxDev/ReTyper.git
cd ReTyper
swift build -c release
.build/release/ReTyper
```

After installing, launch ReTyper — it will appear in the menu bar. Grant **Accessibility** and **Input Monitoring** permissions when prompted.

> [!NOTE]
> **"ReTyper is damaged and can't be opened"** — this happens because the app is not signed with an Apple Developer certificate. Fix it with:
>
> ```bash
> xattr -cr /Applications/ReTyper.app
> ```
>
> Then open the app again.

## Permissions

ReTyper needs two macOS permissions to function:

| Permission           | Why                                                            |
| -------------------- | -------------------------------------------------------------- |
| **Accessibility**    | To read focused text and selection, validate the range, and send replacement input |
| **Input Monitoring** | To detect hotkey presses (modifier key double-tap)             |

Grant both in **System Settings → Privacy & Security**.

## Settings

Click the layout indicator in the menu bar to access settings:

- **Autostart After Login** — launch at macOS startup
- **Play Switching Sound** — audible feedback on switch
- **Manual Switching** — choose modifier key and single/double tap
- **Switch Only Last Word** — convert only the last typed word
- **Active Keyboards** — pick your Latin and Cyrillic layouts

## Known limitations

Актуальный объём на 2026-09-06:

- **В терминалах и полях без подтверждённых условий редактирования замена отменяется до отправки текста.** Полная поддержка [Terminal](https://support.apple.com/guide/terminal/welcome/mac) отложена по решению пользователя «Безопасная отмена пока». Читаемый экран и диапазон экранного выделения не доказывают положение курсора командной строки. Удаления серией Backspace и внутреннего буфера набранного текста нет.
- **Проверки возможностей поля не означают поддержку любого приложения.** Для попытки замены нужны роль `AXTextField`, `AXTextArea` или `AXComboBox`, включённое сфокусированное поле без secure-подроли, читаемые согласованные текст и диапазон, доступные на запись `AXValue` и `AXSelectedTextRange`. Это условия допуска, а не доказательство того, как конкретное приложение обработает ввод. В допущенных редактируемых полях сохранены оба режима: последнее слово и текст от начала строки до курсора.
- **Автоматическая замена не использует буфер обмена ни как источник, ни как транспорт.** Текст читается через [Accessibility](https://developer.apple.com/documentation/applicationservices/axuielement), а для замены готовится одна пара событий Unicode с точным локальным чтением обратно. Предел подготовки составляет 4096 единиц UTF-16; платформа может отклонить и более короткий фрагмент. Дробления на несколько вводов нет.
- **Автоматические латинские цели ограничены US, ABC и Polish Pro**, совместимыми с имеющейся QWERTY-таблицей. Остальные раскладки могут оставаться в ручном выборе, но не получают результат по неподходящей таблице; если совместимой цели нет, исходник сохраняется. Кириллические Apple/PC-варианты определяются по точному ID. Неоднозначный белорусский апостроф при обратной конвертации всегда даёт `]` без Shift; восстановить исходное состояние Shift по тексту невозможно.
- **Передача события процессу не подтверждает замену в поле.** Успех требует повторного чтения полного ожидаемого текста, пустого выделения и правильного курсора. Событие в очереди можно отменить, но после `handedOff` нельзя обещать атомарность поля или отзыв ввода. При неизвестном или частичном результате исходный фрагмент остаётся только в памяти, новые замены блокируются, слепой автоматический откат не выполняется. Единственное исключение: полностью подтверждённый преобразованный текст с неверным курсором допускает одну адресную попытку восстановления с проверкой, без повторов. Поздно подтверждённый полностью корректный результат считается успехом, без отката.
- **Ручное восстановление требует явного действия.** `Copy Original Text` записывает сохранённый фрагмент в буфер обмена только по нажатию и заменяет его текущее содержимое; это единственная запись в буфер обмена. После проверки поля пользователь может подтвердить `Clear Recovery`: исходник будет удалён из памяти и новые замены разрешены, но уже переданное событие этим не отменяется. Выход ждёт текущую операцию и предупреждает о потере сохранённого исходника; после завершения процесса копия не сохраняется.
- **Диагностика локальная и ограниченная.** `~/Library/Caches/com.retyper.app/retyper.log` содержит только метаданные, не пользовательский текст; предел файла 1 MiB, права каталога `0700`, файла `0600`. Запись вынесена из горячего пути и может пропускаться при перегрузке.

Полная матрица приложений и целевых систем не заявлена проверенной. Фактические подтверждения и ограничения: [отчёт проверки](specs/001-fix-retype-text-replacement/verification.md); согласованные условия этого patch-релиза и перенесённые проверки: [release gate](specs/001-fix-retype-text-replacement/release-gate.md).

## Disclaimer

This app was made for personal use. You're welcome to use it, but it comes with **no warranty** of any kind. The author is **not responsible** for any issues, data loss, or other problems that may arise from using this software. Use at your own risk.

## License

MIT
