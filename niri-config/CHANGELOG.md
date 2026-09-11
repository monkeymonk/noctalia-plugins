# Changelog

## 1.1.0

A full-repository audit and remediation round. Four data-safety bugs, the
edit pipeline's architecture, and the cost of every save.

### Fixed
- **Editing a nested single-line block no longer destroys its siblings.**
  `input { keyboard { xkb { layout "us" } numlock } }` — the style niri's own
  default config ships — lost `keyboard`, `xkb` and `numlock` when `layout` was
  edited. Line-oriented edits now refuse to expand past a node that shares its
  line, so `;`-separated siblings survive too.
- **Deleting a script works.** The delete button assigned an undeclared
  property, threw, and left the panel wedged on `busy`.
- **Monitor live preview applies all five properties.** Mode, scale, transform,
  position and VRR raced one shared process, so at most one reached niri; they
  now drain through a queue.
- **A failed Apply no longer destroys the previous backup.** `.bak` is refreshed
  only by a run that passes `niri validate`, and a rejected Apply now also
  removes a file it created, leaving the tree byte-identical to before.
- **Undo cannot lie.** The restore script reports how many files it actually
  restored; the success message and the Undo button are gated on that count.
- **`XDG_CONFIG_HOME` is honoured**, as niri itself does — the plugin no longer
  reads and writes a config niri does not load when it is set elsewhere.
- **No more writes outside the include graph.** The `cfg/display.kdl` /
  `cfg/misc.kdl` fallbacks are used only when the resolved include graph loads
  them, else the file that already owns the section, else `config.kdl`.
  Previously the setting silently did nothing while validate passed.
- **Reloading can no longer discard another tab's staged edits** without
  warning; a programmatic reload refuses while changes are pending.
- Validate stderr goes to `mktemp` instead of a predictable world-writable path.
- An invalid monitor position produces no command instead of a truncated argv.

### Added
- The Input tab's layout / variant / option fields get pickers driven by the
  system's xkb database. The fields stay free text, so `layout "us,de"` survives.
- Full 13-language coverage for the strings this release introduces, and two
  stale translations corrected (the reload tooltip, and the external-editor
  description, which documented a `$VISUAL`/`$EDITOR` fallback that was never
  implemented).

### Changed
- The write pipeline moved out of `Panel.qml` into `SaveController.qml`, the
  non-visual counterpart to `ConfigModel.qml`. Staging and immediate raw writes
  are now separate calls instead of one function with a hidden flag.
- Staging an edit emits its own signal, so it no longer triggers the work a
  disk reload does: a single save used to re-parse the layout file 26 times,
  fork three processes in the Monitors tab, and rebuild 50+ shortcut rows.
  Reading a section now parses once; a Save applies all its edits in one pass.
- Toggling a shortcut updates that row in place instead of rebuilding the whole
  list, so the scroll position is kept; filtering excludes rows from the model
  rather than hiding built ones.
- Block-level KDL editing moved into `lib/kdl.js` — it existed only as four
  diverged copies inside section QML, the one layer the pure core was missing.
  `lib/input.js` and `lib/layout.js` now own those two tabs' parse/diff/apply.
- The five modals declared inline inside sections are now reusable components,
  and every picker/editor takes a translate function instead of the whole panel.
- Removed the unreachable Raw section, seven uncalled library exports and ~250
  dead translation entries.

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
