# Changelog

## 1.0.1

- Translations for 12 languages (fr, de, es, it, nl, pt, ru, pl, ja, ko-KR,
  zh-CN, zh-TW); English remains the fallback.

## 1.0.0

Initial release — a full GUI editor for the niri configuration.

### Editing model
- **Staged changes + Apply**: edits are staged (shown live, not written); the
  header **Apply** button writes all staged files atomically — `.bak` each →
  write → `niri validate` → hot-reload, **restoring every backup if validation
  fails**. **Undo** reverts the last apply; **reload** discards staged changes.
- **Surgical KDL editing**: only the changed node is touched; comments, blank
  lines and alignment are preserved byte-for-byte. Auto-detects your `include`
  graph and edits each section in the file that already owns it.

### Section editors (verified against the niri 26.04 docs)
- **Shortcuts**: browse/filter/add/edit/delete/enable-disable binds; live key
  capture, special-key list, niri action picker, app/script picker for `spawn`,
  conflict detection.
- **Monitors**: live detection (`niri msg outputs`), mode/scale/transform/
  position/VRR/off/backdrop, non-destructive live preview, add disconnected
  monitors. Optional **Monique** profile switching when its CLI is installed.
- **Input**: full keyboard/touchpad/mouse/general option set.
- **Workspaces**: named workspaces + `open-on-output`.
- **Window rules**: capture a live window to prefill `match`; full open/placement/
  sizing/appearance props; unmodeled props preserved on edit.
- **Layout**: gaps, centering, presets, focus-ring/border/shadow/tab-indicator/
  insert-hint, struts.
- **Animation**: global disable/slowdown, per-event easing + spring tuning.
- **Autostart**, **Misc** (cursor/hotkey-overlay/clipboard/overview/…), and a
  **Scripts** manager (`~/.config/niri/scripts/`, app-toggle template).

### Quality of life
- Per-tab **file path** + **Edit file** button and a **niri docs** link.
- Pure `.pragma library` core (KDL parser, niri IPC, per-section logic) with no
  QML/Noctalia coupling, for eventual Noctalia v5 portability.
- Node test suite covering the parser, lib logic vs live `niri msg`, and the
  sandboxed apply/validate/rollback/undo path.
