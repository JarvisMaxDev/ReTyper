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
| **Accessibility**    | To select, copy and paste text with key presses and to check whether the focused field has a selection |
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

Актуально на 2026-09-24:

- **Замена идёт через выделение и буфер обмена, как в 0.9.0.** Без выделения ReTyper выделяет текст клавишами редактора (⌘⇧←, в режиме последнего слова затем ⇧→), копирует его и вставляет преобразованный текст поверх выделения. Через 0,5 с прежнее содержимое буфера возвращается, если за это время туда ничего не скопировали. Временный текст помечен маркерами nspasteboard.org, поэтому менеджеры буфера его не сохраняют; сам скопированный фрагмент они записать могут.
- **Копирование без выделения не выполняется, если поле сообщает, что выделения нет.** Так исправлено дублирование вида `ghbdtпривет` в редакторах, которые при пустом выделении копируют всю строку. Для приложений на Electron ReTyper для этого один раз за запуск включает их дерево [Accessibility](https://developer.apple.com/documentation/applicationservices/axuielement). Для полей, которые о выделении ничего не сообщают, сохраняется порядок 0.9.0.
- **Прежнее содержимое буфера никогда не вставляется вместо текста.** Если копирование не сработало, меняется только раскладка. Отдельного удаления через Backspace нет.
- **В терминалах и защищённых полях меняется только раскладка.** Вставка также не выполняется, если во время операции нажата клавиша или переключено приложение.
- **Режим последнего слова отделяет слова только пробелами**, поэтому буквы на клавишах пунктуации (ж, э, х, б, ю) остаются частью слова.
- **macOS 15.4 и новее может спросить разрешение на вставку из других приложений**, потому что ReTyper читает буфер обмена программно. Разрешить можно в диалоге или в Системных настройках → Конфиденциальность и безопасность.
- **Автоматические латинские цели ограничены US, ABC и Polish Pro**, совместимыми с имеющейся QWERTY-таблицей. Остальные раскладки могут оставаться в ручном выборе, но не получают результат по неподходящей таблице; если совместимой цели нет, исходник сохраняется. Кириллические Apple/PC-варианты определяются по точному ID. Неоднозначный белорусский апостроф при обратной конвертации всегда даёт `]` без Shift; восстановить исходное состояние Shift по тексту невозможно.
- **Диагностика локальная и ограниченная.** `~/Library/Caches/com.retyper.app/retyper.log` содержит только метаданные, не пользовательский текст; предел файла 1 MiB, права каталога `0700`, файла `0600`. Запись вынесена из горячего пути и может пропускаться при перегрузке.

Полная матрица приложений и целевых систем не заявлена проверенной. Решение и история прежнего пути: [спецификация](specs/001-fix-retype-text-replacement/spec.md).

## Disclaimer

This app was made for personal use. You're welcome to use it, but it comes with **no warranty** of any kind. The author is **not responsible** for any issues, data loss, or other problems that may arise from using this software. Use at your own risk.

## License

MIT
