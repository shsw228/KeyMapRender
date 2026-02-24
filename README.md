# KeyMapRender

[![CI](https://github.com/shsw228/KeyMapRender/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/shsw228/KeyMapRender/actions/workflows/ci.yml?query=branch%3Amain)

[日本語版 README](README.ja.md)

KeyMapRender is a macOS utility that shows a semi-transparent keyboard overlay while a configurable key is held down (or toggled), focused on Vial/VIA-compatible keyboards.

## Features
- Show/hide keyboard overlay with configurable trigger key behavior
- Read Vial keymap data from connected devices (Raw HID / Python bridge)
- Render layer-aware key labels and update active layer display
- Select layout options from `layouts.labels` / `layout_options`
- Export `vial.json`, copy diagnostics, and inspect permission status

## Requirements
- macOS (Xcode build environment)
- Accessibility permission
- Input Monitoring permission

## Build
1. Open `KeyMapRender.xcodeproj` in Xcode.
2. Build and run `KeyMapRender`.
3. Grant permissions from `System Settings > Privacy & Security` when prompted.

## Verified Device (Current)
- Agar mini

## Project Docs
- Specification: `docs/specification.md`
- LUCA migration notes: `docs/luca_migration_plan.md`

## License
- This repository is licensed under **GNU General Public License v3.0**.
- See `LICENSE` for details.
- Third-party licenses can be viewed from the app menu (`Third-Party Licenses…`) and are bundled under:
  - `KeyMapRender/Resources/python_deps/hidapi-0.15.0.dist-info/licenses/`
