# Changelog

All notable changes to this plugin are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-09-11

### Added

- `toggle()` on the `plugin:fingerprint-manager` IPC target, so
  `qs -c noctalia-shell ipc call plugin:fingerprint-manager toggle` works —
  previously it was a silent no-op while the sibling plugin supported it.

### Fixed

- The enrollment progress bar reads the reader's real stage count from
  `net.reactivated.Fprint.Device.num-enroll-stages` over D-Bus instead of
  assuming 10. The tested Goodix 27c6:609c reports **13**, so the bar was
  under-reporting on every enrollment; 10 remains the fallback.

### Changed

- The 30-second `fprintd-list` poll now runs only while the panel is visible.
  Every mutation path and the manual refresh button already refreshed the list.
- `FingerCard`'s `deleteRequested` carries the finger name, so the card works
  outside a `Repeater` instead of recovering identity from a delegate closure.
- The finger picker and both confirmation modals moved out of `Panel.qml` into
  `Components/FingerPicker.qml` and a parameterized `Components/ConfirmPopup.qml`
  that replaces two near-identical inline copies.

## [1.1.1] — 2026-06-09

### Added

- Translations for 12 languages (fr, de, es, it, nl, pt, ru, pl, ja, ko-KR, zh-CN, zh-TW); English remains the fallback.

## [1.1.0] — 2026-05-19

### Added

- Control-center shortcut (`controlCenterWidget`) that toggles the panel.
- `showInControlCenter` setting (default `true`) with a toggle in the plugin settings to hide it without removing it from the control-center layout.

## [1.0.0] — 2026-05-19

### Added

- Panel UI to list, enroll, delete, and test fingerprints via `fprintd`.
- Bar widget with fingerprint icon that toggles the panel.
- Settings UI to customise the bar widget icon colour.
- IPC target `plugin:fingerprint-manager` with `openPanel()`.
- Translatable strings with `{name}` placeholder support; English bundled.
- Periodic refresh (30 s) so external `fprintd` changes show up automatically.
- Per-finger delete confirmation modal.
- Detection of missing `fprintd` binary with a dedicated error state.
