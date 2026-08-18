# Changelog

All notable changes to AppTimer are documented here. The project follows semantic versioning: patch releases protect correctness, minor releases add compatible capabilities, and major releases may alter data or workflow concepts.

## 2.0.1 — SwiftData launch fix

### Fixed

- Removed a duplicate physical model checksum from the staged SwiftData migration plan. Existing V1/V2 local stores now migrate directly and lightweightly to V3 instead of causing an early app termination before the Menu Bar item appears.

## 2.0.0 — Private Timeline and retro annotations

### Added

- Added `ContextSegment` through SwiftData schema V3 with a lightweight V2 → V3 migration stage; historic V1/V2 models remain unchanged.
- Added an opt-in, local-only passive application-context recorder. It stores only app display name, bundle identifier, and start/end timestamps, with a 30-day default retention period, 7/30/90-day or indefinite options, heartbeat recovery, and full-history deletion.
- Added a Dashboard Timeline with a daily app-context lane, separate manual project lane, day navigation, and a detailed segment list.
- Added retro session creation from a selected Timeline range. Projects must be selected explicitly; intersecting manual sessions require an explicit **Trim** or **Replace** policy.

### Changed

- Report calculations now intersect manual sessions with passive context where available and retain historical `AppSegment` data as a fallback.
- Added a dedicated [Privacy and Timeline Boundary](Docs/Privacy.md) document and updated both README languages with the opt-in collection boundary.

### Verified

- Expanded XCTest for ContextSegment recording, retention, manual/context intersection clipping, historical report fallback, and trim/replace overlap handling.

## 1.7.0 — Core architecture and migration safety

### Changed

- Split the monolithic `AppTimerStore` into `SessionService`, `FocusService`, and `ReminderService`; the Store now coordinates UI-facing state and local system integrations.
- Replaced direct `UserDefaults` wrappers and manual `focusSettingsRevision` invalidation with observable, typed `AppTimerSettings` while retaining all existing preference keys.
- Added versioned SwiftData schemas (`AppTimerSchemaV1`, `AppTimerSchemaV2`) and `AppTimerSchemaMigrationPlan` before the Timeline feature changes persistent models.

### Verified

- Added isolated XCTest coverage for settings persistence and sanitization, session recovery, focus completion and cooldowns, unassigned reminders, and migration-plan version boundaries.
- Documented the migration contract in `Docs/SwiftDataMigration.md`.

## 1.5.1 — Verified release pipeline

### Fixed

- Isolated SwiftUI presentation types on the main actor so the project compiles under the strict concurrency checks of the GitHub macOS runner.
- Created every SwiftData model used by XCTest within an isolated in-memory `ModelContainer`, removing test dependence on an app-level active container.

### Release

- Ships from a clean, green tag-driven workflow that builds the DMG, publishes its SHA-256 file, and records a GitHub build provenance attestation.

## 1.5.0 — Project quality foundation

### Added

- A shared XCTest target with coverage for allocation modes, interval clipping, open sessions, application exclusions, and Focus Companion duration calculations.
- A `Makefile` with reproducible `make build`, `make test`, `make install`, `make dmg`, and `make clean` commands.
- GitHub Actions CI for every push and pull request, plus a tag-driven release workflow that tests, builds a DMG, generates a SHA-256 file, and attaches build provenance.
- MIT License and an English-first README with a Russian counterpart.

### Changed

- DMG files are ignored for future commits; release artifacts are distributed through GitHub Releases.

## 1.4.3 — Local data integrity

- Added a session heartbeat and interrupted-session recovery to prevent long periods after a crash from being counted as work.
- Added a Dashboard banner to review, edit, or delete a recovered interval.
- Started monitors and reminders at application launch rather than on the first Menu Bar interaction.
- Replaced silent SwiftData read and save failures with local diagnostics and an explicit status.

## 1.4.0 — Calm Focus

- Added Focus Pulse states, 25/50/90-minute focus sessions, a focus ring, and a seven-day focus heatmap.

## 1.3.0 — Focus Companion

- Added configurable work, neutral, and distracting application roles with local distraction reminders.

## 1.2.0 — Project details and reports

- Added session editing, notes, client details, hourly rates, weekly goals, expanded CSV export, application exclusions, idle pause, and recent projects.

## 1.1.0

- Added launch at login, global shortcut, CSV export, application exclusions, session deletion, and a weekly overview.

## 1.0.0

- Initial public release with manual multi-project time tracking and three allocation modes.
