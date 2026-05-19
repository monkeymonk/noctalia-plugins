# Changelog

All notable changes to this plugin are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
