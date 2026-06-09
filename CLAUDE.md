# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Noctalia Shell plugin **source repository**, structured per the upstream
[noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins) convention:
each plugin lives in its own directory at repo root with a `manifest.json` +
optional QML entry-point files. Plugins so far:

- `fingerprint-manager/` — panel UI that shells out to the `fprintd-*` CLI.
- `niri-config/` — a GUI editor for the niri config; surgical KDL editing with a
  staged-apply → `niri validate` → auto-rollback model, a pure-JS `.pragma
  library` core (zero QML/Noctalia deps, for eventual v5 portability), and a Node
  test suite. See `niri-config/README.md`.

Plugins are QML/JavaScript with **no build step**. New plugins go in sibling dirs.

When publishing as a Noctalia source, each plugin dir also needs a `README.md`,
a `preview.png` (16:9 @ 960x540), and a `repository` field in its manifest. The
top-level `registry.json` is auto-generated from manifests by
`scripts/build-registry.py` (run in CI on push) — **don't hand-edit it**; run the
script if you need it locally.

## Install / iterate

Symlink the specific plugin directory (not the repo root) into Noctalia:

```bash
ln -s "$PWD/<plugin>" ~/.config/noctalia/plugins/<plugin>
```

Noctalia scans the plugins folder **only at shell startup**, so a newly symlinked
plugin needs a restart to appear. There is **no reload IPC** (`ipc call shell
reload` does not exist). Restart the shell — from a context that has the Wayland
env (`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, …):

```bash
qs -c noctalia-shell kill && setsid -f qs -c noctalia-shell
```

For tighter iteration, enable the per-plugin **development / hot-reload** toggle
in **Settings → Plugins → Installed** (reloads on file change without a restart).
Enable the plugin there and assign it to a bar/panel slot. Trigger panels via IPC
(matches each `Main.qml` `IpcHandler`):

```bash
qs -c noctalia-shell ipc call plugin:<id> openPanel
qs -c noctalia-shell log -f      # follow shell logs (QML errors, icon warnings)
```

Validation is manual (reload, open the panel, exercise it) plus, for `niri-config`,
`node niri-config/test/*.test.js`.

## Noctalia plugin gotchas (learned the hard way)

- **Icons are Tabler icons** resolved via `Icons.get(name)` (see
  `/etc/xdg/quickshell/noctalia-shell/Commons/IconsTabler.qml`, ~6000 names). An
  **unknown name renders a "skull" fallback** and logs `… doesn't exist in the
  icons font`. Validate names against that file. Gotchas: monitor = `device-desktop`
  (not `monitor`), window = `app-window` (not `window`/`windows`), layers =
  `stack-2` (not `layers`), app = `app-window` (not `application`).
- **QML property names**: cannot start with an uppercase letter (`KNOWN` →
  load error) and cannot shadow a FINAL `Item` property (`opacity`, `scale`,
  `state`, …) — prefix them (`winOpacity`). qmllint does **not** catch these; they
  fail at load. Check the shell log after a reload.
- **Launch external programs with `Quickshell.execDetached([...])`, never a
  `Process`.** A `Process` is killed when its owning QML object is destroyed, and
  panels are dismissed on focus loss — so a program launched via `Process` dies
  the moment the user clicks it. `execDetached` survives. Same for opening files /
  file managers (`xdg-open`): a bare terminal `$EDITOR` can't launch without a TTY.
- **Widgets** (from `qs.Widgets`): `NText`, `NButton`, `NIconButton`, `NToggle`,
  `NTextInput`, `NComboBox` (`model: [{key,name}]`, `currentKey`, `onSelected`),
  `NColorChoice`, `NCollapsible`, `NScrollView` (set `horizontalPolicy:
  ScrollBar.AlwaysOff` + bind content `width:` to the scrollview's `availableWidth`
  for full-width content). `NDivider` uses `vertical: true` (not `orientation`).
  Sizes/colors only via `Style.*` / `Color.m*` — no literal px or hex.
- **`pluginApi`** is injected (never construct it): `tr(key)`, `pluginSettings`,
  `saveSettings()`, `manifest`, `openPanel`/`togglePanel`/`withCurrentScreen`.
  Plugin settings persist in `~/.config/noctalia/settings.json` under the plugin
  id; `manifest.metadata.defaultSettings` are the fallbacks.
- **Strings** go through a local `tr(key, fallback)` that proxies `pluginApi.tr`
  and falls back to the literal on a missing key / `!!key!!` sentinel — always
  pass an English fallback and add the key to `i18n/en.json` in the same change.
- **Capturing `preview.png`**: panels open on the focused screen / near their bar
  widget. `scripts/make-preview.sh` uses `slurp` (interactive). For a clean shot,
  switch to an empty workspace first (`niri msg action focus-workspace N`).
- **Noctalia v5** is a C++/Luau rewrite — v4 QML plugins won't run on it. Keep
  non-UI logic in pure `.pragma library` JS (it ports; the QML shell is rewritten).

## Architecture (`fingerprint-manager/`)

Entry points are declared in `fingerprint-manager/manifest.json` — `Main.qml` (background IPC handler), `Panel.qml` (UI), and `BarWidget.qml` (toolbar entry). Both receive a `pluginApi` injected by Noctalia; never construct one.

Data flow is one-directional and process-driven:

- `Panel.qml` owns four `Quickshell.Io.Process` instances: `listProcess`, `deleteProcess`, `deleteAllProcess`, `verifyProcess`. `EnrollDialog.qml` owns its own `enrollProcess`.
- Reads (`fprintd-list`) buffer stdout via `StdioCollector` and parse on `onStreamFinished`. Long-running interactive commands (`fprintd-enroll`, `fprintd-verify`) stream via `SplitParser.onRead` and dispatch to `fprintUtils.js` classifiers.
- All output parsing lives in `fprintUtils.js` (`.pragma library` — stateless, shared). The classifiers (`classifyEnrollLine`, `classifyVerifyLine`) match on `fprintd` status tokens like `enroll-stage-passed`, `verify-match`, etc. When extending behaviour, add new tokens here rather than scattering string matches across QML.
- Polkit auth for enroll/delete is handled by the system's polkit agent (e.g. `hyprpolkitagent`); the plugin does not authenticate.
- The user is always `Quickshell.env("USER")` — never hardcode.

UI conventions (provided by Noctalia, imported as `qs.Commons` / `qs.Widgets`): use `NText`, `NButton`, `NIcon`, `NIconButton`, `NDivider`, `NScrollView` rather than raw `QtQuick.Controls`. Sizes/colors come from `Style.*` and `Color.m*` — do not introduce literal pixel values or hex colors.

Strings go through `root.tr(key, fallback)`, which proxies `pluginApi.tr` and falls back to the literal when the key is missing or returns the `!!key!!` sentinel. Always pass an English fallback so the UI degrades gracefully; add the key to `i18n/en.json` in the same change.

## Device-specific assumption

`EnrollDialog.qml` hardcodes `totalStages: 10` (typical for Goodix 27c6:609c). The progress bar clamps via `Math.min`, so over-reporting devices are fine, but if you support a device with a different stage count, prefer reading it from `fprintd-enroll` output rather than changing the constant.
