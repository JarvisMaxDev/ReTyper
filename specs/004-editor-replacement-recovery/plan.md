# Implementation Plan: восстановление редактора по метаданным копирования

**Ветка**: `main` · **Дата**: 2026-10-01 · **Spec**: [spec.md](spec.md)

## Summary

Локальная реализация выполнена и проверена. VS Code использует отдельный ограниченный протокол
copy/metadata вместо недостоверного AX-диапазона. Дизайн и границы —
[metadata-implementation.md](metadata-implementation.md); результаты — [verification.md](verification.md).

## Technical Context

- [Swift](https://www.swift.org/) 5.9, существующие Cocoa/Carbon/CoreFoundation.
- macOS 12+, Universal Binary arm64/x86_64; живая проверка — macOS 26.6.2 arm64.
- Контекст поля подтверждается по запуску процесса, окну, элементу и DOM-классу.
- Свежие `vscode-editor-data` подтверждают одиночное выделение; whole-line copy от каретки
  отбрасывается, неизвестная metadata не разрешает вставку.
- Clipboard snapshot в памяти, восстановление по поколению с учётом внешнего Copy/Cut.
- Новых разрешений, пользовательских preferences или runtime-зависимостей нет.
- Обычная замена 100 символов проверена за 0,191–0,245 с до наблюдаемого сохранённого документа.

## Constitution Check

Конституция 8.0.0 содержит явно согласованный узкий probe-copy для подтверждённого редакторного
поля VS Code. Системные раскладки, локальность, отсутствие текста в логах, запрет предварительного
удаления, исключение терминала/secure input и отмена при смене получателя сохранены.

Локальные unit/build/package/live gates выполнены в объёме [verification.md](verification.md).
По отдельному запросу владельца опубликован **v0.10.1**, CI ревизии `5929d83` прошёл;
публичные DMG/ZIP и Homebrew cask проверены. Подробности — в `verification.md`.
Ограничения живой матрицы и отдельное невоспроизведённое изменение clipboard зафиксированы в отчёте.

## Project Structure

- `Sources/ReTyper/EditorCopyMetadata.swift` — парсер ограниченного Pickle/JSON.
- `Sources/ReTyper/EditorMetadataFlow.swift` — последовательность действий по подтверждённой metadata.
- `SystemReplacementHost.swift`, `AppDelegate.swift`, `KeyboardMonitor.swift` — контекст, clipboard,
  secure input и внешние события.
- `Tests/ReTyperTests/Editor*Tests.swift` — новые проверки, полный набор 96/96.
- `Tools/ReTyperStand/EditorRecoveryDriver.swift`, `EditorRecoveryGuards.swift` — настоящие хоткеи,
  обычная и отрицательная матрицы; [инструкция](../../Tools/ReTyperStand/EDITOR-RECOVERY.md).
- `build.sh`, `scripts/test-build-path.sh` — защита от упаковки устаревшего бинарника.

## История и следующий шаг

Старый план не переименован в успешный: [plan-ax-preparation.md](plan-ax-preparation.md),
[tasks-ax-preparation.md](tasks-ax-preparation.md) хранят отклонённую гипотезу и её FAIL.
Текущие задачи — [tasks.md](tasks.md), начиная с T031, чтобы не переиспользовать исторические ID.
Терминальная 003 остаётся отдельной незавершённой фичей. Следующее действие — пользовательская
проверка v0.10.1 на остальных компьютерах и разбор конкретных воспроизводимых сбоев.
