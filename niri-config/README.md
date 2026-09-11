# Niri Config

A Noctalia panel to **view and edit your [niri](https://github.com/YaLTeR/niri)
configuration** from a GUI — shortcuts, monitors, input, workspaces, window
rules, layout, animations, autostart, misc, and a managed scripts folder.

It shells out to `niri` (`niri msg`, `niri validate`) and edits your existing
`*.kdl` files **surgically**: only the node you change is touched, and every
comment, blank line and column alignment around it is preserved byte-for-byte.

## How edits are applied (the safety model)

Changes you make are **staged**, not written immediately:

1. Editing anything (toggle, field, add/edit/delete an item) updates the live
   view but **not the file**. The header shows *“N unsaved changes”* and the
   **Apply** button lights up.
2. **Apply** writes every staged file atomically: it `.bak`s each file, writes,
   runs **`niri validate`** on the whole config, then hot-reloads niri — and if
   validation fails it **restores every `.bak`** and shows the error (your staged
   edits are kept so you can fix and re-apply).
3. **Undo** (after an Apply) restores the backups and reloads.
4. The **reload** button discards staged changes and re-reads from disk.

So a bad edit can never reach a running niri, and nothing is reformatted.

## Requirements

- **niri** on `PATH` (uses `niri msg` and `niri validate`).
- **Noctalia** ≥ 4.4.3.

Install from Noctalia: **Settings → Plugins → Sources**, add this repository's
URL, then enable **Niri Config** under **Available** and assign it to a bar slot.

Your config layout is auto-detected — the plugin resolves your `config.kdl`
`include` graph and edits each section in the file that already owns it
(`cfg/keybinds.kdl`, `cfg/input.kdl`, …, following the niri/noctalia convention).

## What's in each tab

| Tab | What you can do |
| --- | --- |
| **Shortcuts** | Browse/filter all binds; add/edit/delete; enable/disable (KDL slashdash). Live **key capture**, special-key list (media/wheel), action picker over niri's action vocabulary, and an app/script picker for `spawn`. Conflict detection. |
| **Monitors** | Live detection via `niri msg outputs`; per-monitor mode/scale/transform/position/VRR/off/backdrop, with non-destructive **live preview** (`niri msg output`). Add a config for a disconnected monitor. Optional **Monique** profile switching (see below). |
| **Input** | Keyboard (xkb layout/variant/options/model, track-layout, numlock, repeat), touchpad (tap, dwt/dwtp, natural-scroll, drag, accel speed/profile, scroll & click method, tap-button-map, …), mouse, and general (mod-key, warp-mouse, focus-follows-mouse, …). |
| **Workspaces** | Named workspaces (live status from `niri msg workspaces`); add/rename/delete; per-workspace `open-on-output`. |
| **Window rules** | List/add/edit/delete/enable-disable; **capture a live window** (`niri msg windows`) to prefill `match`; open behavior, placement, sizing, opacity, corner-radius, block-out-from, and more. Unmodeled props are preserved on edit. |
| **Layout** | Gaps, centering, presets, focus-ring/border/shadow/tab-indicator/insert-hint, struts, colors. |
| **Animation** | Global disable/slowdown, per-event enable + easing duration/curve, and spring tuning (damping/stiffness/epsilon). |
| **Autostart** | `spawn-at-startup` / `spawn-sh-at-startup` entries; add/edit/delete/toggle via app picker or raw command. |
| **Misc** | prefer-no-csd, screenshot-path, cursor, hotkey-overlay, clipboard, overview. |
| **Scripts** | Create/edit/delete named helper scripts in `~/.config/niri/scripts/` (auto-`chmod +x`), with a focus-or-spawn (app-toggle) template. Scripts show up in the Shortcuts action picker. |

Every tab shows the **file it edits** with an **Edit file** button (opens it in
your file manager, or an editor if you set one — see Settings), and a **doc
link** to the matching niri wiki page.

## Monique integration (optional)

If the [`monique`](https://github.com/noctalia-dev/noctalia-plugins) CLI (monitor
profile manager) is installed, the Monitors tab shows a **Profiles** list instead
of per-monitor editing: switch profiles in place, or **New / edit** to open the
Monique GUI. With Monique absent, the plugin manages monitors itself, writing to
the niri/noctalia default `cfg/display.kdl`. (You can disable the standalone
Monique bar plugin — switching lives here.)

## Settings

- **Icon color**, **Show in control center**.
- **External editor command** — e.g. `ghostty -e nvim`. Leave empty and the
  *Edit file* buttons open the file's folder in your file manager instead (a bare
  terminal `$EDITOR` can't launch without a TTY).

## Architecture

All niri logic lives in pure, framework-agnostic `lib/*.js` (`.pragma library`)
modules with **zero QML/Noctalia dependencies** — they take text in and return
text/data out. The QML only does file IO, runs processes, and renders. This is
deliberate: Noctalia v5 is a C++/Luau rewrite where v4 QML plugins won't run, so
when its plugin API lands only the thin UI shell needs re-implementing.

| Module | Responsibility |
| --- | --- |
| `lib/kdl.js` | tolerant KDL v2 parser with source ranges + surgical edit primitives |
| `lib/config.js` | resolve the `include` graph, map sections → owning file |
| `lib/fileblob.js` | read N files in one process, split the marker-delimited blob |
| `lib/binds.js` | bind model/serialization, conflict detection, action vocabulary |
| `lib/keys.js` | Qt key event → niri keysym; special-key list |
| `lib/niri.js` | `niri msg` builders, JSON parsers, validated multi-file apply/undo |
| `lib/input.js`, `lib/layout.js` | descriptor-driven parse/diff/apply for the Input and Layout tabs |
| `lib/rules.js`, `outputs.js`, `desktop.js`, `scripts.js`, `monique.js` | per-section models/serialization + external-tool integration |
| `lib/xkb.js` | parses the system's xkb layout/variant/model/option list from `evdev.lst`; drives the Input tab's pickers (the layout/variant/option fields stay free text so comma-separated multi-layout setups survive) |

## IPC

```txt
target plugin:niri-config
  function openPanel(): void
  function toggle(): void
```

```bash
qs -c noctalia-shell ipc call plugin:niri-config openPanel
```

## Tests

The pure core is unit-tested against your **real** config and live `niri msg`,
and the write path is exercised entirely in a `/tmp` **sandbox copy** — it never
touches `~/.config/niri`:

```bash
node test/kdl.test.js          # parser safety + batched child edits vs your real *.kdl
node test/libs.test.js         # binds/keys/niri/desktop/outputs/xkb vs live data
node test/input.test.js        # input model: parse / diff / edit serialization / apply
node test/layout.test.js       # layout model incl. preset blocks
node test/save.sandbox.test.js # apply + niri validate gate + auto-restore + undo (sandboxed)
```

## Generating the registry preview

```bash
./scripts/make-preview.sh   # opens the panel via IPC, slurp to select, crops to 960×540
```

## Translations

User-facing strings live in `i18n/en.json`. Copy to `i18n/<locale>.json` and
translate the values; keep `{placeholders}` intact.
