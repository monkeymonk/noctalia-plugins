# Fingerprint Manager (v5)

A Noctalia v5 plugin to enroll, delete, and test fingerprints from a panel UI.
Wraps the `fprintd-*` CLI, so any reader supported by `libfprint` works
(tested on a Goodix fingerprint sensor over `fprintd`).

This is the Luau/TOML port of the original v4 QML plugin
(`../fingerprint-manager`), built for Noctalia's native-C++ v5 plugin system
(TOML manifest, isolated Luau entry scripts, declarative `ui.*` panels). The
v4 directory is kept as read-only history; it does not load under v5.

## Installation

Requires Noctalia >= v5.0.0-beta.9 (plugin API 24: argv-array `noctalia.runAsync`).

For local use, add the `noctalia-plugins` repo root (not this directory
itself) as a path source, then enable the plugin by id. Noctalia scans a
path source for subdirectories that each contain their own `plugin.toml`
(the same convention the official/community git source repos use) - a path
source pointed directly at this directory finds no plugin to enable.

```bash
noctalia msg plugins source add fingerprint-manager-v5 path /path/to/noctalia-plugins
noctalia msg plugins enable monkeymonk/fingerprint-manager
```

Then add the bar widget from **Settings -> Bar -> Add widget** (listed as
"Fingerprint Manager"), and/or add the **Fingerprint Manager** tile from
**Settings -> Control Center Shortcuts**. Both just toggle the same panel.

If `enable` logs `cannot enable 'monkeymonk/fingerprint-manager': parse
error: File could not be opened for reading` and the plugin stays disabled,
retry the command. This was observed during development as a transient
Noctalia-side failure under heavy concurrent plugin-source file activity
(not specific to this plugin - a stock official plugin hit the identical
message under the same conditions); it is not caused by anything in this
plugin's files.

### System dependencies

Install `fprintd` - it provides the daemon plus the
`fprintd-list`/`enroll`/`delete`/`verify` CLI tools the plugin shells out to
(pulls in `libfprint` automatically):

| Distro | Command |
| --- | --- |
| Arch / CachyOS | `sudo pacman -S fprintd` |
| Debian / Ubuntu | `sudo apt install fprintd` |
| Fedora | `sudo dnf install fprintd` |
| openSUSE | `sudo zypper install fprintd` |

`fprintd` is D-Bus activated - there's no service to enable.

### Polkit agent

Enroll and delete trigger a polkit auth prompt, so a polkit authentication
agent must be running. KDE Plasma and GNOME start one automatically. On
Hyprland, niri, or other minimal setups, install one and launch it from your
compositor's autostart. Examples:

- `hyprpolkitagent` (Arch: `sudo pacman -S hyprpolkitagent`) - start with
  `systemctl --user enable --now hyprpolkitagent.service`
- `polkit-gnome` - `exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1`
- `polkit-kde-agent` - `exec-once = /usr/lib/polkit-kde-authentication-agent-1`

### Verify the reader is detected

```bash
fprintd-list "$USER"
```

A line like `No fingerprints enrolled for user ...` means the daemon found
your sensor. `No devices available` means `libfprint` doesn't recognise it -
check `lsusb` and the
[libfprint supported devices list](https://fprint.freedesktop.org/supported-devices.html).

## What it does

- Lists currently enrolled fingers for the active user, refreshed manually
  and every 30s while the panel is open
- Enrolls a new finger with live per-stage progress
- Deletes one finger (inline confirm on the row) or all of them (inline
  confirm on the actions row)
- Quick "Test match" using `fprintd-verify`
- Bar widget and control-center shortcut, both toggling the same panel
- Dedicated empty states for "fprintd not installed" and "no device found"

## Notes

- Shells out to `fprintd-list`, `fprintd-enroll`, `fprintd-delete`,
  `fprintd-verify` - no D-Bus boilerplate.
- `fprintd-list`/`fprintd-delete` use the argv-array form of
  `noctalia.runAsync` (plugin API 24) since the username/finger-name
  arguments are dynamic. `fprintd-enroll`/`fprintd-verify` need line-by-line
  streaming progress, which `noctalia.runStream` only accepts as a shell
  string, so those are built with a shell-quoting helper instead.
- `noctalia.runStream` exposes no handle to stop its child process.
  Cancelling an in-progress enroll kills it by command-line pattern with
  `pkill -f`, the same approach the official `screen_recorder` and
  `mpvpaper` plugins use for subprocesses they don't own a PID for.
- Polkit prompts for enroll/delete come from your system polkit agent; the
  plugin does not handle authentication itself.
- The progress bar's total stage count is read once per panel session from
  `net.reactivated.Fprint.Device.num-enroll-stages` over D-Bus (`busctl`),
  falling back to 10 if that lookup fails.
- v4's `showInControlCenter` setting has no v5 equivalent: the
  control-center shortcut is a normal `[[shortcut]]` entry that the user
  adds/removes from **Settings -> Control Center Shortcuts** like any other
  shortcut, so a plugin-level visibility toggle would be redundant. The
  `iconColor` setting carries over as `icon_color`.

## Translations

User-facing strings live in `translations/en.json` (the only bundled
locale for this v5 port so far). To add a language, copy that file to
`translations/<locale>.json` (ISO codes: `fr`, `de`, `ja`, `zh-CN`, ...) and
translate the values; `noctalia.tr()` falls back to the key when a
translation is missing. Keep placeholders like `{finger}`, `{user}`,
`{count}`, `{max}` intact - they're substituted at runtime via
`noctalia.tr(key, { ... })`.

## IPC

The panel is a standard `[[panel]]` entry, so no custom IPC handler is
needed (v4's `plugin:fingerprint-manager` target is gone):

```bash
noctalia msg panel-toggle monkeymonk/fingerprint-manager:panel
```
