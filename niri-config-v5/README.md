# Niri Config (v5)

A Noctalia **v5** (Luau plugin API) panel to view and edit your
[niri](https://github.com/YaLTeR/niri) configuration from a GUI.

This is a **phase-1 port** of the original [v4 QML plugin](../niri-config/)
(kept at `niri-config/`, unmodified, as the reference/history). Phase 1 wires
**3 of the eventual 10 tabs** — Shortcuts, Monitors, Input — plus the full
KDL engine and the validate-backed save pipeline. The plugin is built so
adding the remaining tabs later is a self-contained addition, not a
rearchitecture (see [Architecture](#architecture)).

## What's in this phase

| Tab | What you can do |
| --- | --- |
| **Shortcuts** | Browse/filter all binds; add/edit/delete; enable/disable (KDL slashdash). Live **key capture** for non-Super combos (the host never delivers Super/Mod chords to a plugin — type those), a special-key picker (media/brightness/system/wheel), an action picker over niri's action vocabulary, and an app/script picker for `spawn`. Conflict detection. |
| **Monitors** | Live detection via `niri msg outputs`; per-monitor mode/scale/transform/position/VRR/off/backdrop, with non-destructive **live preview** (`niri msg output`). Add a config for a disconnected monitor. Optional **Monique** profile switching when the `monique` CLI is installed. |
| **Input** | Keyboard (xkb layout/variant/options/model, track-layout, numlock, repeat), touchpad (tap, dwt/dwtp, natural-scroll, drag, accel speed/profile, scroll & click method, tap-button-map, …), mouse, and general (mod-key, warp-mouse, focus-follows-mouse, …). |

## Deferred to a later phase

Workspaces, Window rules, Layout, Animation, Autostart, Misc, Scripts. These
are simply not in the left nav yet — no "coming soon" placeholders. Adding
one is: write `lib/tabs/<name>.luau` against the tab contract documented at
the top of `panel.luau`, append one entry to `panel.luau`'s `TAB_MODULES`
list, done.

## How edits are applied (the safety model)

Unchanged from v4: changes are **staged**, not written immediately.

1. Editing anything updates the live view but **not the file**. The header
   shows *"N unsaved change(s)"* and the **Apply** button lights up.
2. **Apply** writes every staged file: it backs each up to `.bak`, writes,
   runs **`niri validate`** on the whole config, then hot-reloads niri — and
   if validation fails it **restores every `.bak`** and shows the error
   (your staged edits are kept so you can fix and re-apply).
3. **Undo** (after an Apply) restores the backups and reloads.
4. The **reload** button discards staged changes and re-reads from disk
   (refuses while changes are staged, so it can never silently discard
   work).

So a bad edit can never reach a running niri, and nothing is reformatted —
only the node you change is touched; every comment, blank line and column
alignment elsewhere is preserved byte-for-byte.

## Requirements

- **niri** on `PATH` (uses `niri msg` and `niri validate`).
- **Noctalia** v5.2.0+ in practice (uses `plugin_api = 24`: argv-array
  `noctalia.runAsync`, `require()` modules, `capture_keys`/`onKey`, and
  function-closure UI callbacks — see [Architecture](#architecture) for why
  this level and not higher).
- **monique** (optional) — if installed, the Monitors tab shows a Profiles
  list instead of per-monitor editing.

Install: **Settings → Plugins → Sources**, add this repository, enable
**Niri Config**, assign the bar widget or the control-center shortcut.

Your config layout is auto-detected — the plugin resolves your
`config.kdl` `include` graph and edits each section in the file that
already owns it (`cfg/keybinds.kdl`, `cfg/input.kdl`, …, following the
niri/noctalia convention).

## Settings

- **External editor command** — e.g. `ghostty -e nvim`. Leave empty and the
  *Edit file* buttons open the file's folder in your file manager instead.
- **Icon color** — bar widget glyph color.
- **Show in control center** — v5's widget/shortcut placement is entirely
  host/user-owned (add or remove the control-center tile the same way as
  any other widget, from Settings → Control Center shortcuts); this setting
  is the closest honest equivalent available through the `shortcut.*` API —
  it enables/disables the tile rather than hiding it.

## Architecture

```
plugin.toml          manifest: panel/widget/shortcut entries, settings,
                      capture_keys (300 non-Super key/modifier combos)
panel.luau            chrome: header (Apply/Undo/Reload/docs), file-path row,
                      data-driven left nav, dispatches into one tab's render()
widget.luau            bar glyph, toggles the panel
shortcut.luau          control-center tile, toggles the panel
lib/
  kdl.luau             tolerant KDL v2 parser + surgical edit primitives —
                       the safety-critical core everything else is built on
  config.luau           include-graph resolution (config.kdl -> owning file)
  state.luau             load (sync, no subprocess) / stage / apply / undo
                         orchestration — the read+write pipeline
  niri.luau               `niri msg`/`validate` command builders, JSON
                         parsers, the embedded backup+validate+rollback and
                         undo shell scripts
  binds.luau               bind model, conflict detection, serialization,
                         the niri action vocabulary
  keys.luau                 special-key list (XF86/Wheel), onKey-chord ->
                         niri-combo-token translation
  outputs.luau               `output {}` block model + KDL serialization
  monique.luau                 monique CLI command builders + JSON parser
  xkb.luau                       evdev.lst layout/variant/model/option parser
  input.luau                       `input {}` settings descriptor table +
                         parse/diff/apply
  desktop.luau                      .desktop entry parsing, command<->action
  scripts.luau                       managed-scripts directory listing (+
                         templates, ready for the deferred Scripts tab)
  tabs/
    shortcuts.luau                   Shortcuts tab (list/add/edit/delete/
                         enable-disable, capture, pickers)
    monitors.luau                      Monitors tab (live detection, edit,
                         preview, Monique profiles)
    input_tab.luau                       Input tab (settings form)
translations/en.json                       mandatory label_key/description_key
                         text for the 3 plugin settings (runtime panel UI
                         text is plain English literals, matching the
                         official example plugins' actual practice — v5
                         does not require `noctalia.tr()` for ordinary
                         `ui.label` text the way v4 required i18n for all
                         QML strings)
```

### What changed porting QML → Luau (beyond syntax)

- **No subprocess batching needed for reads.** v4's `ConfigModel.qml` read
  every config file through a single `cat`-with-markers `Process` (see v4's
  `lib/fileblob.js`) specifically to avoid spawning one process per file.
  `noctalia.readFile(path)` is a synchronous **in-process** call, so
  `state.luau`'s `load()` just reads the main file + every include directly
  — no subprocess, no `lib/fileblob.js` port exists.
- **No subprocess needed for `command -v niri`/`command -v monique`.**
  `noctalia.commandExists(name)` replaces both of v4's `checkInstalledCmd`/
  `checkCmd` Process calls with a synchronous in-process check.
- **No base64 needed for file content.** v4 used `Qt.btoa(text)` when
  handing file contents to a QML `Process.command`, because QML's argv
  handling needed that safety margin. `noctalia.runAsync({...}, cb)`'s
  argv-array form (`plugin_api = 24`) passes each array element as one
  literal argument with **no shell parsing**, so raw KDL text travels
  straight through to the embedded `sh -c` apply/undo/write scripts as a
  real argv slot (`"$2"` etc.) — those scripts write it with
  `printf %s "$c" > "$f"` instead of `base64 -d`.
- **The KDL scanner reads byte codes, not substrings.** The straightforward
  port of `kdl.js`'s character-by-character `text[i]` scanning (1-char
  `string.sub` per test) measurably exceeded the Luau host's per-callback
  CPU budget on a real ~10KB `keybinds.kdl` — a few hundred binds' worth of
  quoted args/props means hundreds of thousands of single-character
  `string.sub` allocations per parse. `lib/kdl.luau` scans with
  `string.byte` (no allocation) and reads quoted-string bodies in chunks
  (find the next backslash/closer, slice once) instead of one
  `table.insert` per character — verified with `noctalia.nowMs()` at ~15ms
  for a full real-world `keybinds.kdl` parse, comfortably inside budget.
- **No popup/dialog primitive.** Every v4 `Popup` (BindEditor, ActionPicker,
  AppPicker, MonitorEditor, MonitorAddDialog, ConfirmPopup) becomes an
  in-tab screen swap — see the tab-module contract at the top of
  `panel.luau`.
- **Live key capture is structurally limited.** v4 used a generic Qt
  keyboard grab (`Keys.onPressed`) that could see every physical key,
  including the Super/Mod key practically every real niri bind uses. v5
  panels can only receive a **pre-declared, finite** list of chords via
  `capture_keys`/`onKey`, and the host **unconditionally rejects any Super
  chord** ("those belong to the compositor") — there is no manifest trick
  around this. `plugin.toml` declares 300 chords (every letter/digit/
  F-key/named-key, bare + ctrl/alt/shift) so live capture works for
  everything *except* Super combos; the combo text field remains the
  primary entry method, exactly as it already was in v4 ("stays editable as
  a fallback for other layouts").

### `plugin_api = 24` — why this level

Cumulative capabilities actually used: argv-array `noctalia.runAsync`
(level 24, avoids shell-quoting entirely for the apply/undo/write scripts'
dynamic paths and content), `require()` relative modules (22), the
`capture_keys` panel option + `onKey` (13), function-closure `ui.*`
callbacks (9), the `dismiss_on_outside_click` panel default (8) — all below
24, so 24 is the binding constraint. No feature introduced by a level above
24 is used (no `tooltip` on non-button containers, no `ui.colorPicker`, no
`height = "content"`, etc.), so the plugin stays compatible with the widest
practical range of v5 releases above its floor.

## What a next phase should reuse vs. rebuild

**Reuse as-is** (stable, tested, zero UI dependency): `lib/kdl.luau`,
`lib/config.luau`, `lib/state.luau`, `lib/niri.luau`, `lib/desktop.luau`,
`lib/scripts.luau`. A Workspaces/Rules/Layout/Animation/Autostart/Misc/
Scripts tab needs **zero changes** to any of these — Scripts in particular
already has its full data layer (`lib/scripts.luau`'s template builders)
sitting unused, waiting only for a `lib/tabs/scripts.luau` UI.

**New small descriptor/model modules per tab**, following the pattern
`lib/input.luau` and `lib/outputs.luau` already establish (a flat
`SETTINGS`-style table + parse/diff/apply, or a `parseX`/`serializeX` pair
operating on `kdl.luau` nodes) — expect one of these per new tab for
Layout/Animation/Misc (settings-table shaped, like Input) and Workspaces/
Window-rules/Autostart (block-list shaped, like Shortcuts/Monitors).

**`panel.luau`'s chrome needs zero changes** to add a tab — append one
`TAB_MODULES` entry and, if the new tab needs a doc link, one `DOC_URLS`
entry.

## Testing discipline

There is no Luau unit-test runner equivalent to v4's `node test/*.test.js`
shipped with this plugin (nothing to install, nothing to run — Luau plugins
have no package manager or test harness of their own). Every `lib/*.luau`
module was instead verified, during development, with a throwaway
self-test **service** entry enabled against the real, running Noctalia
instance: parser invariants mirroring `test/kdl.test.js` (byte-identical
round-trip edits against every file in a real `~/.config/niri`), and the
full apply → validate-reject-and-rollback → undo sequence mirroring
`test/save.sandbox.test.js`, run **exclusively against a `/tmp` sandbox
copy** (`lib/state.luau`'s `State.new(configRoot)` takes an explicit
config-directory override for exactly this purpose — never exposed as a
user-facing setting). Those harness files are not part of the shipped
plugin; see the task's final report for the exact commands and results.
