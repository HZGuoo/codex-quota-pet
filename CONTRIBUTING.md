# Contributing to Codex Quota Pet

[简体中文](docs/CONTRIBUTING.zh-CN.md)

Contributions are welcome for compatibility fixes, tests, documentation,
accessibility, observability exports, and focused UI improvements.

## Before starting

- Open an issue before a large feature or protocol change. Describe the user or
  maintainer workflow and expected compatibility impact.
- Do not submit authentication tokens, account information, proxy credentials,
  prompts, responses, private paths, or private session contents.
- Preserve support for macOS 13, Apple Silicon, and Intel unless an issue has
  agreed on a compatibility change.
- Avoid new runtime dependencies unless the issue explains why they are needed.
- Check `ROADMAP.md` and the existing issue forms before proposing overlapping
  work.

## Local development

Build the application and CLI with Swift 6:

```bash
Scripts/build-app.sh
swift build --product codex-observe
```

Run the focused self-test executable when changing parsing, state, proxy, or
export behavior:

```bash
swift run --disable-sandbox CodexQuotaPetSelfTests
```

If the local compiler and SDK do not match, set `CODEX_QUOTA_SDKROOT` to a
compatible macOS SDK for `Scripts/build-app.sh`.

## Pull requests

- Keep each pull request focused on one clear problem.
- Explain user-visible and public-API behavior.
- Add a sanitized fixture for new App Server response shapes.
- Add a regression check for parsing or state changes.
- Update `docs/CORE_API.md` and `CHANGELOG.md` for public API changes.
- Attach before-and-after screenshots for UI changes and check light, dark, and
  multi-display behavior.
- Verify the Universal 2 release build for packaging changes.
- Never log or copy Codex or ChatGPT authentication tokens.

By contributing, you confirm that you have the right to submit the work and
agree to distribute it under the repository license.
