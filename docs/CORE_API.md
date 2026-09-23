# CodexQuotaPetCore API

`CodexQuotaPetCore` is a reusable Swift package for privacy-preserving local
Codex observability. The macOS menu-bar app and `codex-observe` CLI both use the
same library.

## Supported API surface

The following public types are the supported integration surface for the `0.x`
release series:

- `CodexObservabilityClient`: owns a local `codex app-server` process and
  captures a complete snapshot.
- `CodexObservabilitySnapshot`: quota, aggregate token usage, and task-state
  counts at one point in time.
- `CodexObservationExporter`: JSON and CSV export without prompt or response
  content.
- `CodexAppServerClient`: lower-level lifecycle and request API.
- `QuotaSnapshot`, `CodexTokenUsageSnapshot`, and
  `CodexTaskStatusSummary`: typed domain models.
- `CodexRolloutEventParser` and `CodexLocalTokenUsageParser`: parsers for the
  minimum local metadata needed by offline tools.

Breaking API changes may occur before `1.0`, but they will be documented in
`CHANGELOG.md`. Consumers should pin a minor version while the package is `0.x`.

## Swift Package Manager

```swift
dependencies: [
    .package(
        url: "https://github.com/HZGuoo/codex-quota-pet.git",
        branch: "main"
    )
]
```

Add `CodexQuotaPetCore` to the target dependencies, then capture a snapshot.
Pin the first `0.3.x` tag instead of `main` after the observability API is
included in a release.

```swift
import CodexQuotaPetCore

let client = CodexObservabilityClient()
try await client.start()
defer { Task { await client.stop() } }

let snapshot = try await client.capture()
let json = try CodexObservationExporter.export(snapshot, format: .json)
```

The client reuses the user's existing local Codex login. It does not expose or
persist credentials.

## CLI

```bash
swift run codex-observe --format json
swift run codex-observe --format csv > codex-usage.csv
swift run codex-observe --codex-path /opt/homebrew/bin/codex
```

JSON is intended for tools and archived snapshots and includes `schemaVersion`.
CSV uses a stable header and
separate `quota`, `token_usage`, and `task` rows for spreadsheets and local
analysis.

## Stability and privacy

The project treats prompt text, response text, authentication tokens, and proxy
credentials as out of scope for observability exports. New exported fields must
be aggregate metadata and must be documented in `PRIVACY.md`.
