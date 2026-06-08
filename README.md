# Noctalia Plugins

A collection of plugins for [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell).

Layout follows the upstream [noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins) registry convention: each plugin lives in its own directory at the repo root.

## Plugins

| Plugin | Description |
| --- | --- |
| [Fingerprint Manager](./fingerprint-manager/README.md) | Enroll, delete, and test fingerprints via `fprintd`. |
| [Niri Config](./niri-config/README.md) | GUI editor for your [niri](https://github.com/YaLTeR/niri) config — shortcuts, monitors, input, window rules, layout and more, with a staged-apply + `niri validate` + auto-rollback safety model. |

## Installation

In Noctalia, open **Settings → Plugins → Sources**, add this repository's URL, then install the desired plugin from **Settings → Plugins → Available**.

See each plugin's README for plugin-specific requirements and usage.
