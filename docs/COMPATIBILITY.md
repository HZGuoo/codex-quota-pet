# Compatibility matrix

Compatibility is verified against sanitized protocol fixtures and selected live
installations. A check mark means the maintainer verified the listed workflow;
it is not a guarantee for every account or workspace configuration.

| Codex source | Version | Quota | Daily usage | Task states | Verified |
| --- | --- | --- | --- | --- | --- |
| ChatGPT desktop bundled Codex | Current as of 2026-09-04 | ✅ | ✅ | ✅ | 2026-09-04 |
| Codex CLI | Current as of 2026-09-04 | ✅ | ✅ | ✅ | 2026-09-04 |

Exact upstream build numbers were not recorded for the initial verification, so
the table does not claim them. Future entries should include the output of
`codex --version`, macOS version, architecture, and the fixture or issue that
demonstrates compatibility.

## Reporting a compatibility problem

Use the compatibility issue form and include:

- `codex --version`
- macOS version and architecture
- whether Codex comes from ChatGPT desktop, npm, or another package
- which capability failed
- a minimal sanitized error message

Do not attach authentication tokens, complete App Server output, prompts,
responses, or private repository paths.
