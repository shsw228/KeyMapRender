# KeyMapRender

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
