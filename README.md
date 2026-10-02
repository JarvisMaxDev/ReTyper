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

ReTyper has no built-in character tables. On every hotkey press it asks macOS what each key
prints, with and without Shift, in the layouts you selected, for the keyboard you are typing on
(ANSI, ISO or JIS). Letters, digits, punctuation and Shift+digit symbols all convert key by key,
so `^)` typed on Polish becomes `:)` on Russian – PC.

| Script   | Layouts offered in «Active Keyboards» (macOS name → input source ID)                                                                                                       |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cyrillic | Russian → `Russian`, Russian – PC → `RussianWin`, Ukrainian → `Ukrainian-PC`, Ukrainian – Legacy → `Ukrainian`, Belarusian → `Byelorussian`                                 |
| Latin    | U.S., ABC, Polish, German, French, British, Dvorak, Colemak and the other Latin layouts in the list; any selected Latin layout is a valid target |

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
bash build.sh
open ReTyper.app
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

Актуально для [v0.10.1](https://github.com/JarvisMaxDev/ReTyper/releases/tag/v0.10.1), 2026-10-01:

- **Замена идёт через выделение и буфер обмена, как в 0.9.0.** Без выделения ReTyper выделяет текст клавишами редактора (⌘⇧←, в режиме последнего слова затем ⇧→), копирует его и вставляет преобразованный текст поверх выделения. Через 0,5 с прежнее содержимое буфера возвращается, если за это время туда ничего не скопировали. Временный текст помечен маркерами nspasteboard.org, поэтому менеджеры буфера его не сохраняют; сам скопированный фрагмент они записать могут.
- **Копирование без выделения не выполняется, если поле сообщает, что выделения нет.** Так исправлено дублирование вида `ghbdtпривет` в редакторах, которые при пустом выделении копируют всю строку. Для приложений на Electron ReTyper для этого один раз за запуск включает их дерево [Accessibility](https://developer.apple.com/documentation/applicationservices/axuielement). Для полей, которые о выделении ничего не сообщают, сохраняется порядок 0.9.0.
- **Для редакторного поля [VS Code](https://github.com/microsoft/vscode) есть отдельный проверенный путь.** Оно может сообщать нулевой диапазон даже при настоящем выделении. ReTyper делает пробное копирование и проверяет свежие служебные метаданные редактора: результат «скопирована строка без выделения» отбрасывается; заменяется только подтверждённое одиночное выделение. Режим экранного диктора и настройки редактора не включаются. Поддержаны строка, последнее слово, символы и пользовательское выделение в обе стороны. Встроенная терминальная панель, поиск и неподтверждённые поля не получают этот обход; многокурсорный результат или неизвестный формат метаданных приводят только к смене раскладки. Проверена версия 1.138.0, включая обычный пользовательский профиль. [Результаты проверки](specs/004-editor-replacement-recovery/verification.md).
- **Прежнее содержимое буфера никогда не вставляется вместо текста.** Если копирование не сработало, меняется только раскладка. Отдельного удаления через Backspace нет.
- **[Терминал macOS](https://support.apple.com/guide/terminal/welcome/mac): исправляется только набранный фрагмент** (до 256 символов) или его последнее слово. История, автодополнение и вставленный текст не используются. Enter, Tab, стрелки, перемещение курсора, сочетания Command/Control, мышь и смена окна/приложения сбрасывают фрагмент. Мёртвые клавиши, композиция, ввод с Option и переполнение приостанавливают накопление до следующего сброса. Clipboard не используется. На время замены ввод кратко задерживается: Enter доставляется после исправления или отмены. Полноэкранные программы внутри терминала не гарантируются. Другие терминалы и встроенные терминалы редакторов пока поддерживают только смену раскладки.
- **Парольные поля не исправляются.** В обычных редакторах проверяется защита фокусного поля; глобальный Secure Input другого приложения сам по себе не запрещает замену. Система при этом может блокировать доставку хоткея. **В терминале при системном Secure Input запись и замена отключены.** Скрытый ввод без системной защиты (например, `read -s` в [zsh](https://www.zsh.org/)) считается обычным: хранится только в памяти до Enter/сброса. Ввод пользователя или смена приложения в обычном редакторе по-прежнему отменяют вставку.
- **Режим последнего слова отделяет слова только пробелами**, поэтому буквы на клавишах пунктуации (ж, э, х, б, ю) остаются частью слова.
- **macOS 15.4 и новее может спросить разрешение на вставку из других приложений**, потому что ReTyper читает буфер обмена программно. Разрешить можно в диалоге или в Системных настройках → Конфиденциальность и безопасность.
- **Преобразуются не только буквы, но и символы на тех же клавишах.** Соответствия берутся из выбранных раскладок macOS для текущего типа клавиатуры; ручных таблиц нет. Направление определяется так:
  1. Если во фрагменте есть буквы — по большинству букв. Латинскими считаются и буквы с диакритикой (`ü`, `ł`).
  2. Если букв нет — по символам, которые есть только в одной раскладке пары (`^` → латинская, `№` → кириллическая).
  3. Если и таких символов нет — по текущей раскладке (`:)` при RU → `^)`).

  Если направление не определить, текст не меняется, переключается только раскладка. Повторное нажатие хоткея возвращает исходный фрагмент.
- **Коллизии и особенности раскладок Apple.** Если один символ дают несколько клавиш, при обратном преобразовании побеждает клавиша без Shift, затем меньший код клавиши; поэтому белорусский апостроф даёт `]`. В Russian – PC на ANSI-клавиатуре Shift+`` ` `` печатает латинскую `Ë`, а не `Ё` — ReTyper повторяет систему. Символы, которых нет на клавишах основного блока (эмодзи, `—`, слой Option), не меняются.
- **Диагностика локальная и ограниченная.** `~/Library/Caches/com.retyper.app/retyper.log` содержит только метаданные, не пользовательский текст; предел файла 1 MiB, права каталога `0700`, файла `0600`. Запись вынесена из горячего пути и может пропускаться при перегрузке.

Полная матрица приложений и целевых систем не заявлена проверенной. Решение и история прежнего пути: [спецификация](specs/001-fix-retype-text-replacement/spec.md). Преобразование символов из системных раскладок: [спецификация 002](specs/002-symbol-conversion/spec.md).

## Disclaimer

This app was made for personal use. You're welcome to use it, but it comes with **no warranty** of any kind. The author is **not responsible** for any issues, data loss, or other problems that may arise from using this software. Use at your own risk.

## License

MIT
