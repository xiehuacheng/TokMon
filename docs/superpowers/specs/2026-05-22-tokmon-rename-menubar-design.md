# TokMon Rename and Menu Bar Display Design

> **状态：** 本设计已实现。App 已重命名为 TokMon，菜单栏使用自定义 N+ Cursor Trace 模板图标，并支持在设置窗口配置菜单栏显示项。后续代码演进（如新增 Kimi Quota 显示开关）以当前源码为准。

## Summary

Rename the macOS app from AgentMon back to TokMon, with TokenMonitor used as the expanded name in documentation and explanatory surfaces. Replace the existing generic menu bar chart symbol with the approved custom Cursor Trace N+ template icon, and let users choose whether the menu bar shows only the icon or one core metric next to it.

## Goals

- Present the app to users as TokMon.
- Keep TokenMonitor available as the long-form product name.
- Replace the current `chart.line.uptrend.xyaxis` menu bar icon with the approved custom N+ Cursor Trace mark.
- Add a settings-controlled menu bar display mode.
- Keep menu bar metrics focused on quick-glance overview values.
- Preserve existing local TokMon data during the AgentMon to TokMon data directory migration.

## Non-Goals

- Do not add detailed token breakdown metrics to the menu bar.
- Do not redesign the full popover layout beyond the required rename and icon/title updates.
- Do not depend on SF Symbols for the final menu bar mark.
- Do not overwrite an existing TokMon application support directory during migration.

## Naming Scope

The rename is full scope:

- User-visible app name becomes `TokMon`.
- Long-form name is `TokenMonitor`.
- The `.app` bundle becomes `TokMon.app`.
- SwiftPM package, executable, targets, test targets, and module imports move from `AgentMon...` naming to `TokMon...` naming.
- Source files and types using the `AgentMon` prefix are renamed to `TokMon` equivalents.
- README and macOS app documentation use TokMon as the product name.
- Packaging metadata uses TokMon for bundle name and display name.

## Data Directory Migration

The default macOS app data directory changes from:

```text
~/Library/Application Support/AgentMon
```

to:

```text
~/Library/Application Support/TokMon
```

Startup directory resolution must preserve user data:

- If the TokMon data directory exists, use it and do not touch the AgentMon directory.
- If the TokMon directory does not exist and the AgentMon directory exists, move AgentMon to TokMon.
- If the move fails, surface a clear startup error rather than silently starting with an empty database.
- If neither directory exists, create and use the TokMon directory as normal.

This preserves the SQLite database, scan state, config, and model pricing created under the old app name.

## Menu Bar Icon

Use the approved N+ Cursor Trace mark:

- It is based on the earlier Cursor Trace concept, rotated counterclockwise 90 degrees.
- It keeps the vertical token trace visually dominant.
- It extends the horizontal cursor stroke slightly from the N variant.
- It is rendered as a custom template `NSImage` in AppKit code.
- It should adapt to light/dark menu bar appearances through template tinting.

The icon replaces the current `chart.line.uptrend.xyaxis` SF Symbol.

## Menu Bar Display Modes

Add a persisted setting for the menu bar display mode. Supported values:

- `Icon Only`
- `Total Tokens`
- `Est. Cost`
- `Requests`

Do not include:

- `Input Tokens`
- `Output Tokens`
- `Cache Created`
- `Cache Hit`
- `Hit Rate`

Those detailed values remain available inside the popover.

## Menu Bar Behavior

The menu bar item uses variable length:

- `Icon Only` displays only the N+ template icon.
- Metric modes display the N+ template icon plus a formatted value.
- Total tokens and requests use compact number formatting, for example `42.8K`.
- Estimated cost uses existing cost formatting, for example `$1.28`.
- Missing data displays a conservative placeholder, such as `-`, without expanding into long error text.
- Engine startup errors keep the menu bar item usable so users can still open the popover/settings or quit.

The metric values use the same current source/range state as the popover summary.

## Settings UI

Add a `Menu Bar` section to the native settings window.

The section includes a compact picker labeled `Display` bound to the persisted menu bar display mode. It should follow existing settings window styling and spacing.

Saving settings persists the selected mode to `tokmon-ui-state.json`.

## Runtime Refresh

The menu bar needs current values even when the popover is not open. The runtime should start a lightweight stats observation path on app launch or otherwise refresh enough state to keep the menu bar title current.

Opening the popover can continue to trigger the existing full refresh behavior. Avoid duplicate concurrent refreshes by reusing the existing stats store guardrails.

## Compatibility

Existing `tokmon-ui-state.json` files that lack the new field default to `Icon Only`.

The JSON value should be stable and machine-oriented, such as:

```json
"menuBarDisplayMode": "iconOnly"
```

Invalid or unknown values default to `iconOnly`.

## Testing

Add or update tests for:

- UI state config loading defaults missing `menuBarDisplayMode` to icon-only.
- UI state config saves and reloads the selected display mode.
- Settings draft load/save round-trips the menu bar display mode.
- Menu bar formatting covers icon-only, total tokens, estimated cost, requests, and missing data.
- Data directory resolution migrates AgentMon to TokMon only when the TokMon directory does not already exist.
- Packaging metadata and build script references produce `TokMon.app`.
- Renamed SwiftPM package/target/test imports compile.

Manual verification after implementation:

- Run `cd macos-app && swift test`.
- Run `git diff --check`.
- Run `bash macos-app/scripts/build-app.sh`.
- Launch `macos-app/release/TokMon.app` and confirm the menu bar icon, display picker, metric values, popover title, and existing data migration behavior.
