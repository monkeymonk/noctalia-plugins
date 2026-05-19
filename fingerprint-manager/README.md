# Fingerprint Manager

A Noctalia plugin to enroll, delete, and test fingerprints from a panel UI. Wraps the `fprintd-*` CLI, so any reader supported by `libfprint` works (tested on Framework 13 AMD with Goodix 27c6:609c).

## Installation

Requires Noctalia ≥ 4.4.3. Install this plugin from Noctalia: **Settings → Plugins → Sources**, add this repository's URL, then enable **Fingerprint Manager** under **Available**.

### System dependencies

Install `fprintd` — it provides the daemon plus the `fprintd-list`/`enroll`/`delete`/`verify` CLI tools the plugin shells out to (pulls in `libfprint` automatically):

| Distro | Command |
| --- | --- |
| Arch / CachyOS | `sudo pacman -S fprintd` |
| Debian / Ubuntu | `sudo apt install fprintd` |
| Fedora | `sudo dnf install fprintd` |
| openSUSE | `sudo zypper install fprintd` |

`fprintd` is D-Bus activated — there's no service to enable.

### Polkit agent

Enroll and delete trigger a polkit auth prompt, so a polkit authentication agent must be running. KDE Plasma and GNOME start one automatically. On Hyprland or other minimal setups, install one and launch it from your compositor's autostart. Examples:

- `hyprpolkitagent` (Arch: `sudo pacman -S hyprpolkitagent`) — start with `systemctl --user enable --now hyprpolkitagent.service`
- `polkit-gnome` — `exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1`
- `polkit-kde-agent` — `exec-once = /usr/lib/polkit-kde-authentication-agent-1`

### Verify the reader is detected

```bash
fprintd-list "$USER"
```

A line like `No fingerprints enrolled for user …` means the daemon found your sensor. `No devices available` means `libfprint` doesn't recognise it — check `lsusb` and the [libfprint supported devices list](https://fprint.freedesktop.org/supported-devices.html).

## What it does

- Lists currently enrolled fingers for the active user
- Enrolls a new finger (modal with live progress)
- Deletes one finger or all of them (with confirmation)
- Quick "Test match" using `fprintd-verify`
- Optional bar widget with a fingerprint icon that toggles the panel

## Notes

- Shells out to `fprintd-list`, `fprintd-enroll`, `fprintd-delete`, `fprintd-verify` — no D-Bus boilerplate.
- Polkit prompts for enroll/delete come from your system polkit agent; the plugin does not handle authentication itself.
- The progress bar's total stage count defaults to 10 (typical for Goodix 609c). The bar clamps at 100% if the device reports fewer stages.

## Generating the registry preview

`preview.png` (16:9 @ 960x540) is the image Noctalia shows in the plugin registry. To regenerate it, open the panel in Noctalia and run:

```bash
./scripts/make-preview.sh
```

`slurp` will prompt you to drag a selection over the panel; the script captures it with `grim` and resizes to the registry-mandated dimensions. Requires `grim`, `slurp`, and ImageMagick.

## Translations

All user-facing strings live in `i18n/en.json`. To add a language, copy that file to `i18n/<locale>.json` (ISO codes: `fr`, `de`, `ja`, `zh-CN`, `zh-TW`, …) and translate the values. Keep placeholders like `{finger}`, `{user}`, `{count}`, `{max}` intact — they're substituted at runtime.

## IPC

```txt
target plugin:fingerprint-manager
  function openPanel(): void
```

Example:

```bash
qs -c noctalia-shell ipc call plugin:fingerprint-manager openPanel
```
