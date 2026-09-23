# Roadmap

This roadmap lists concrete maintenance work. It does not promise dates. Open an
issue before starting a large item so scope and compatibility can be reviewed.

## Current: observability foundation

- Stabilize `CodexQuotaPetCore` as a reusable Swift package.
- Ship the `codex-observe` JSON and CSV command-line exporter.
- Maintain sanitized App Server fixtures and an explicit compatibility matrix.
- Publish a Developer ID-signed and Apple-notarized release.
- Publish the validated cask in a public Homebrew tap.
- Complete the English-first documentation and community issue forms.

## Next: evidence and diagnostics

- Record task duration, approval wait time, failure, interruption, and retry
  counters without storing conversation content.
- Add a redacted diagnostics bundle that users can inspect before attaching it
  to an issue.
- Add an explicit export schema version and migration notes.
- Verify compatibility against recorded Codex versions and both architectures.
- Document reproducible release-download and Homebrew-install metrics in
  `ADOPTION.md`.

## Later: portable integrations

- Evaluate a headless exporter for environments where AppKit is unavailable.
- Evaluate OpenTelemetry-compatible local metrics output.
- Provide examples for maintainer dashboards and release-workflow diagnostics.
- Add localization only after contributors volunteer to maintain it.

## Contribution candidates

These are suitable for focused external contributions after an issue agrees on
scope:

- Add fixture-driven checks for the files in `Fixtures/app-server`.
- Add JSON Schema files for exported snapshots.
- Add a `--pretty`/`--compact` JSON option to `codex-observe`.
- Improve accessibility labels and reduced-motion behavior in the quota orb.
- Add an Intel-specific build and smoke-test checklist.
