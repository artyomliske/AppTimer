# Privacy and Timeline Boundary

AppTimer is a local-first macOS application. Its Timeline feature is deliberately separate from manual project tracking: passive application context can describe when an app was active, but it **never** creates a project assignment or a billable session by itself.

## Explicit consent

Passive context recording is disabled by default. It begins only after the user enables **Record application context outside tracking** in Settings. Turning the option off immediately closes the current context segment and stops further collection.

| Category | Stored locally when enabled | Never collected |
|---|---|---|
| Application context | Display name, bundle identifier, start and end timestamps | Window title, document name, web URL, page content |
| Input and screen data | Nothing | Keystrokes, clipboard, screenshots, screen recording |
| Delivery and identity | Nothing | Accounts, cloud sync, telemetry, analytics, network uploads |
| Project data | Explicit manual sessions and project allocations | Automatic project selection or automatic billing |

## Retention and deletion

The default Timeline retention is **30 days**. The user can choose 7, 30, or 90 days, or keep data indefinitely. Automatic cleanup runs locally. The **Delete all passive history** action permanently removes ContextSegment records without deleting projects, manual WorkSession records, invoices, or CSV data.

## Timeline and reports

Timeline draws passive application segments and manual project sessions as separate layers. Creating a retro session requires choosing a project. If it intersects existing manual time, the user explicitly chooses whether to trim or replace the conflicting manual records. Reports use passive context only where it overlaps an explicitly created WorkSession; older sessions continue to use their original AppSegment records.

## Recovery

While a passive segment is open, AppTimer stores only a local heartbeat containing its identifier and recent timestamp. After an unexpected termination, the segment is closed at the last safe heartbeat rather than extended indefinitely.
