# ReTyper

<p align="center">
  <strong>macOS keyboard layout switcher</strong><br>
  Instantly convert mistyped text between Latin and Cyrillic layouts
</p>

<p align="center">
  <a href="https://github.com/JarvisMaxDev/ReTyper/releases/latest">
    <img src="https://img.shields.io/github/v/release/JarvisMaxDev/ReTyper?style=flat-square&label=Download&color=brightgreen" alt="Download latest release">
  </a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue?style=flat-square" alt="macOS 13+">
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
| **macOS**        | 13.0 (Ventura) or later             |
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
| **Accessibility**    | To read and replace selected text via Cmd+C / Cmd+V simulation |
| **Input Monitoring** | To detect hotkey presses (modifier key double-tap)             |

Grant both in **System Settings → Privacy & Security**.

## Settings

Click the layout indicator in the menu bar to access settings:

- **Autostart After Login** — launch at macOS startup
- **Play Switching Sound** — audible feedback on switch
- **Manual Switching** — choose modifier key and single/double tap
- **Switch Only Last Word** — convert only the last typed word
- **Active Keyboards** — pick your Latin and Cyrillic layouts

## Disclaimer

This app was made for personal use. You're welcome to use it, but it comes with **no warranty** of any kind. The author is **not responsible** for any issues, data loss, or other problems that may arise from using this software. Use at your own risk.

## License

MIT
