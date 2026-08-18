# Changelog

All notable changes to AppTimer are documented here. The project follows semantic versioning: patch releases protect correctness, minor releases add compatible capabilities, and major releases may alter data or workflow concepts.

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
