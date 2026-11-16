# Monique Profiles

A minimal Noctalia v5 plugin: a bar widget showing the active
[Monique](https://github.com/ToRvaLDz/monique) monitor profile, and a panel
listing every profile with a click to switch.

Extracted from `niri-config-v5`'s Monitors tab - this is the one piece of
that tool actually used day to day, pulled into its own plugin so there's
far less to break: no KDL parsing, no save/apply/undo pipeline, no niri
logic at all. It only drives `monique --list-profiles` / `--current-profile`
/ `--switch-profile`; Monique owns writing the actual monitor config.

## Requirements

- `monique` on `PATH`.

## Entries

| Entry | Kind | What it does |
| --- | --- | --- |
| `widget` | bar widget | Glyph + active profile name. Click opens the panel. |
| `panel` | panel | Lists every profile; click one to switch to it. |

## Settings

- **Icon color** - defaults to `on_surface` (matches the bar's normal icon
  color); override from Settings -> Plugins.

## IPC

```sh
noctalia msg panel-toggle monkeymonk/monique-profiles:panel
```
