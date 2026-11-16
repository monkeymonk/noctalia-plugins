# Changelog

All notable changes to this plugin are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — 2026-10-23

### Added

- Full Luau/TOML port of the v4 QML plugin (`../fingerprint-manager`) for
  Noctalia v5's native plugin system: `plugin.toml` manifest, `widget.luau`
  (bar), `shortcut.luau` (control-center tile), `panel.luau` (list/enroll/
  delete/test), and a `fingers.luau` module for the finger list/label/icon/
  line-classification logic previously in `fprintUtils.js`.
- `translations/en.json` ported from `i18n/en.json` with one additional key
  (`status.verify-failed`) for a `fprintd-verify` start failure, which the
  v4 version did not distinguish.

### Changed

- Panel: per-finger delete confirmation is now an inline row swap (icon +
  confirm text + check/close buttons) instead of a separate modal popup;
  "enroll" and "delete all" are inline view/row swaps instead of popups,
  since v5 panels render one `ui.*` tree rather than hosting QML `Popup`s.
- `fprintd-list`/`fprintd-delete` now use the argv-array form of
  `noctalia.runAsync` (plugin API 24) instead of a `Process.command` array;
  `fprintd-enroll`/`fprintd-verify` use `noctalia.runStream` with a
  shell-quoted command string (array form isn't available for streaming).
- The IPC target `plugin:fingerprint-manager` (`openPanel`/`toggle`) is
  gone: v5 panels are opened natively with
  `noctalia msg panel-toggle monkeymonk/fingerprint-manager:panel`, so
  `Main.qml`'s `IpcHandler` has no v5 equivalent to port.
- `showInControlCenter` is dropped: the control-center shortcut is a
  standard `[[shortcut]]` entry, added/removed by the user from
  **Settings -> Control Center Shortcuts**, which already does what that
  setting did. `iconColor` carries over as the `icon_color` plugin setting.
- Cancelling an in-progress enroll now kills `fprintd-enroll` by
  command-line pattern (`pkill -f`) instead of `Process.signal(15)`, since
  `noctalia.runStream` exposes no process handle.

### Not carried over

- The 12 non-English translations from the v4 plugin (fr, de, es, it, nl,
  pt, ru, pl, ja, ko-KR, zh-CN, zh-TW) are not yet ported; only English
  ships for now. See README "Translations".
- `scripts/make-preview.sh` and `preview.png` (store listing assets) are not
  carried over; this port targets local `path`-source use, not catalog
  distribution.
