# Native TokMon Menubar Design

Date: 2026-05-18

## Goal

AgentMon will become a macOS-native menubar TokMon app. The product will no longer ship a browser dashboard, and it will no longer expose sessions, skills, MCP, or settings management as user-facing product areas.

The final target is a Swift-native TokMon implementation. During the first migration phase, the current Node/Hono TokMon engine remains only as a verification oracle. It is not the target product architecture.

## Product Boundary

The only user-visible entry point is the macOS status bar icon. Clicking it opens a SwiftUI popover. The popover is the daily TokMon surface and uses a segmented control at the top:

- Overview
- Trends
- Requests
- Sessions

The popover may open a native Swift settings window for heavier configuration. AgentMon should not open a browser dashboard, and the product should not provide general-purpose Claude/Codex session management, skill management, MCP management, or settings editing.

The settings window may include TokMon-specific configuration only:

- Claude Code and Codex usage log paths
- Cost rates
- Default source, range, interval, range mode, live/fixed mode, metric, and refresh interval
- Manual TokMon database rebuild
- Temporary parity verification controls and results while the legacy engine is retained

## Migration Strategy

The migration is B-first with C retained as a verification path:

1. Build the Swift-native TokMon scanner, database, queries, UI state, popover, and settings window.
2. Make the status bar UI read from the native engine by default.
3. Keep the existing Node/Hono TokMon engine temporarily for parity checks.
4. Remove the legacy engine only after parity and UI completeness criteria pass.

The legacy Node/Hono engine must not remain a long-term product dependency. It exists to reduce migration risk while the native scanner and query layer are proven.

## Architecture

### Native Engine

Swift becomes the owner of TokMon runtime behavior:

- Load and save TokMon configuration from the AgentMon application support data directory.
- Scan Claude Code and Codex usage logs.
- Maintain the SQLite database.
- Query summary, trend, heatmap, model, record, and usage session data.
- Provide data directly to SwiftUI stores and views.

Suggested Swift module boundaries:

- `TokMonConfigStore.swift`: loads, normalizes, saves, and migrates TokMon configuration and UI state.
- `TokMonDatabase.swift`: owns SQLite schema setup, migrations, connection handling, inserts, scan state, and database rebuilds.
- `TokMonScanner.swift`: scans Claude Code and Codex logs and writes usage records.
- `TokMonQueryStore.swift`: serves summary, trend, heatmap, records, models, and usage session queries.
- `TokMonParityVerifier.swift`: compares native results against the legacy Node/Hono engine during migration.
- `AgentMonStatsStore.swift`: becomes a UI-facing store backed by native TokMon services instead of URLSession calls.

### Legacy Engine

The current TypeScript TokMon scanner and routes remain temporarily:

- `src/tokmon/scanner.ts`
- `src/routes/tokmon.ts`
- Existing SQLite schema and query behavior used by those routes

The legacy engine should not serve the old web dashboard. Non-TokMon product routes for sessions, skills, MCP, and settings are out of scope for the target product and should not be user-facing after the first migration phase.

### Runtime Model

Opening the popover triggers a refresh and can trigger a scan. While the popover is open, AgentMon refreshes on the configured interval. Closing the popover stops periodic refresh work. The user can still manually trigger a scan.

The native implementation should preserve the low-idle-cost behavior added in v0.1.1 without relying on HTTP activity leases.

## Data And Scanning

### Configuration

Default usage log paths remain:

- Claude Code: `~/.claude/projects`
- Codex: `~/.codex/sessions`

Custom paths remain stored under the AgentMon application support data directory in `tokmon.config.json`. The native settings window can edit these paths.

The old `tokmon-dashboard-state.json` should be replaced by a native `tokmon-ui-state.json` or equivalent. The native implementation should read the old file once when present so users keep their existing source, range, interval, range mode, metric, refresh, and cost preferences.

### Database

The native engine should preserve the existing TokMon tables and semantics unless a migration has a concrete benefit:

- `usage_records`
- `tokmon_scan_state`

At minimum, `usage_records` must continue to capture:

- source
- session id
- model
- input tokens
- output tokens
- cache creation tokens
- cache read tokens
- reasoning tokens
- created time

Scan offsets and related per-file context remain in `tokmon_scan_state`.

### Scanner Parity

The native scanner must match the current TypeScript scanner behavior:

- Scan Claude Code `.jsonl` files under the configured Claude path.
- Scan Codex `.jsonl` files under the configured Codex path.
- Read only appended file ranges when file size grows.
- Skip unchanged files.
- Rescan from zero when a file is truncated.
- Preserve Codex session id and model context when appended usage lines arrive without new metadata.
- Parse Codex `session_meta`, `turn_context`, and `event_msg` token usage entries.
- Subtract Codex cached input tokens from input tokens and store cached input tokens as cache read.
- Store Codex reasoning output tokens.
- Parse Claude assistant message usage.
- Use Claude message id or a usage key to avoid duplicate records.
- Ignore malformed lines and records with no token usage.

## Query Parity

The native query layer must cover the current TokMon API surface:

- summary
- trend by hour or day
- heatmap for recent activity
- models ordered by recent use
- request records with pagination
- usage sessions grouped by session id and source

The native queries must match important existing semantics:

- Date filters use local-time interpretation equivalent to the old `datetime(created_at, 'localtime')` filters.
- Source and model filters apply consistently across summary, trend, heatmap, records, and sessions.
- Trend bucket labels match the existing day and hour formats.
- Cost is computed from the current cost rates and the token columns.
- Request records are ordered newest first.

The general session scanner and full `sessions` table are not part of the target product. If request records need a linked session id, the native TokMon implementation should derive it from usage data or keep only the minimum TokMon-specific linkage needed for request/session drilldown.

## Native UI

### Overview

Overview contains the main controls and status:

- Source control: all, Claude Code, Codex
- Range presets including 1H, 24H, 7D, 30D, and 90D
- Live/fixed mode
- Exact/round range mode
- Hour/day interval
- Metric selection: total tokens, requests, input, output, cache created, cache hit, estimated cost
- Metric tiles for the selected range
- Source breakdown
- Top models
- Scan status and last refreshed time

### Trends

Trends contains richer charting:

- Metric-aware trend chart
- Hour/day bucket support
- Source and model filtering
- 365-day activity heatmap

The native UI should use Swift-native drawing or SwiftUI Charts if available. It must not reintroduce ECharts or web assets.

### Requests

Requests contains the request log:

- Newest-first request records
- Pagination or load-more behavior
- Source, model, range, and metric context
- Token, cache, reasoning, and cost columns
- Expandable row details
- A way to jump from a request to its usage session when a session id is available

### Sessions

Sessions are TokMon usage sessions, not the old general session management feature. This page shows:

- Session id
- Source
- Model context
- Request count
- Total tokens and cost
- First and last usage time
- Drilldown into records for the selected session

No archive, delete, migrate, prompt browsing, skill, MCP, or settings management actions belong in this page.

### Settings Window

The settings window opens from a button in the popover. It contains TokMon-specific settings:

- Source paths
- Cost rates
- Default UI state
- Refresh interval
- Manual rescan
- Manual TokMon database rebuild
- Temporary legacy parity controls while the legacy engine remains

## Error Handling

The native UI should distinguish:

- No data in the selected range
- Missing or unreadable source paths
- Scan errors
- Database open or migration errors
- Malformed log lines ignored during scan
- Legacy parity failures during migration

Errors should be visible in the relevant page or settings window without crashing the popover.

## Validation

### Scanner Tests

Native scanner tests should cover:

- Initial Claude and Codex scans
- Appended usage lines
- Unchanged file skip behavior
- Truncated file rescan behavior
- Codex usage appended without session metadata
- Claude duplicate usage handling
- Cache token and reasoning token parsing
- Malformed JSON lines

### Query Tests

Native query tests should cover:

- Summary totals
- Trend buckets by hour and day
- Heatmap aggregation
- Model list ordering
- Request pagination and ordering
- Usage session aggregation
- Source and model filters
- Local-time date filtering boundaries
- Cost calculation

### Parity Checks

During the migration phase, parity checks compare the native engine against the legacy Node/Hono TokMon engine for the same fixture data:

- Inserted usage records
- Summary
- Trend
- Heatmap
- Models
- Records
- Sessions

Differences should be reported with enough detail to identify whether the scanner, database, query, or time filtering behavior differs.

### App Verification

Before the native implementation is considered complete:

- Swift tests pass.
- Swift build passes.
- TypeScript checks for the retained legacy engine pass while it exists.
- The popover can show Overview, Trends, Requests, and Sessions for empty data, single-source data, multi-model data, and scan error states.
- The settings window can save paths, cost rates, defaults, and refresh interval.

Subjective visual inspection is not required by default; the user prefers to handle visual/UI appearance checks themselves.

## Legacy Removal Criteria

The second phase may remove the legacy engine only after:

- Native scanner parity passes for the agreed fixture set.
- Native query parity passes for summary, trend, heatmap, models, records, and sessions.
- The native popover covers Overview, Trends, Requests, and Sessions.
- The native settings window covers TokMon paths, cost rates, defaults, refresh interval, rebuild, and parity status.
- The app no longer depends on HTTP or Node for user-visible TokMon behavior.

When those criteria pass, remove:

- `public/`
- Static dashboard serving
- Web dashboard screenshots and documentation
- Non-TokMon product routes for sessions, skills, MCP, and settings
- Node runtime packaging from the macOS app bundle
- `package.json`, `package-lock.json`, and TypeScript runtime dependencies if no retained tooling needs them
- Dashboard-specific wording in README, AGENTS, CLAUDE, and macOS app docs

## Out Of Scope

This design does not include:

- A new web dashboard
- A frontend framework
- General session management
- Skill management
- MCP management
- Claude/Codex settings editing
- Deleting the legacy Node/Hono engine before native parity is proven
