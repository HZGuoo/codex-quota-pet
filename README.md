# Codex Quota Pet

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Codex Quota Pet icon">
</p>

<p align="center">
  <strong>Privacy-first local usage and workflow observability for Codex.</strong>
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="https://github.com/HZGuoo/codex-quota-pet/releases/latest">Download</a> ·
  <a href="docs/CORE_API.md">Core API</a> ·
  <a href="ROADMAP.md">Roadmap</a>
</p>

Codex Quota Pet is an open-source macOS monitor and reusable Swift package for
Codex quota windows, aggregate token usage, and top-level task states. It uses
the local `codex app-server` and minimum metadata from local Codex session files.
It never reads or stores authentication tokens, prompts, or response text.

The draggable quota orb is one optional frontend. The reusable
`CodexQuotaPetCore` library and `codex-observe` CLI make the same
privacy-preserving data available to local tools and maintainer workflows.

> [!NOTE]
> This is an unofficial community project. It is not affiliated with or
> endorsed by OpenAI. Codex, ChatGPT, and OpenAI are trademarks of their
> respective owners.

## Why this project exists

Codex exposes task activity in its own interfaces. Codex Quota Pet focuses on
local observability that can be inspected and exported without sending project
data to a maintainer-controlled server.

| Capability | Built-in Codex Pet | Codex Quota Pet |
| --- | --- | --- |
| Animated floating companion | Yes | Optional quota orb |
| Open and follow active chats | Yes | Top-level status shortcuts |
| Subscription quota windows | — | Yes |
| Daily aggregate token history | — | Yes |
| JSON and CSV export | — | Yes, through `codex-observe` |
| Reusable Swift observability API | — | Yes |
| Proxy fail-closed control | — | Yes |
| Project-owned telemetry server | N/A | None |

The comparison reflects the public [Codex Pets documentation](https://learn.chatgpt.com/docs/pets)
as of September 2026. Upstream features can change.

## Features

- Menu-bar display for the most constrained quota window
- Multiple quota buckets, five-hour and weekly windows, reset times, and plan metadata
- Aggregate token totals for today and the last 30 completed calendar days
- Counts for running tasks and tasks waiting for approval or input
- Local system notifications for completion, failure, approval, and input states
- Deep links back to the matching Codex conversation when supported
- Draggable, expandable, always-on-top quota orb with optional click-through
- HTTP and SOCKS5 proxy modes that do not silently fall back to a direct connection
- Manual GitHub release update check
- Reusable Swift API plus JSON and CSV CLI export
- No authentication-token access and no project-owned backend

See [PRIVACY.md](PRIVACY.md) for the exact data boundary.

## Screenshots

### Desktop quota orb

<p>
  <img src="docs/images/pet-compact.png" width="120" alt="Compact desktop quota orb">
  <img src="docs/images/pet-expanded.png" width="420" alt="Expanded desktop quota orb">
</p>

### Menu bar and quick view

<p>
  <img src="docs/images/menu-bar.png" width="130" alt="Menu-bar quota status">
  <img src="docs/images/menu-popover.png" width="420" alt="Menu-bar quick view">
</p>

### Settings

<p>
  <img src="docs/images/settings-general.png" width="32%" alt="Proxy and refresh settings">
  <img src="docs/images/settings-notifications.png" width="32%" alt="Quota orb and notification settings">
  <img src="docs/images/settings-app.png" width="32%" alt="Application settings">
</p>

## Install

Download `CodexQuotaPet-<version>-macos-universal.zip` from
[GitHub Releases](https://github.com/HZGuoo/codex-quota-pet/releases/latest),
unzip it, and move **Codex Quota Pet.app** to Applications.

The current `v0.2.5` artifact is ad-hoc signed. Until a notarized release is
published, macOS may require **Control-click → Open** on first launch. The
repository now contains a Developer ID signing and notarization workflow for
future releases; see [docs/RELEASING.md](docs/RELEASING.md).

To validate the repository-local Homebrew Cask:

```bash
git clone https://github.com/HZGuoo/codex-quota-pet.git
cd codex-quota-pet
brew install --cask ./Casks/codex-quota-pet.rb
```

The cask is ready to move into a public tap after the first notarized release.

## CLI and reusable library

Capture one local observability snapshot:

```bash
swift run codex-observe --format json
swift run codex-observe --format csv > codex-usage.csv
```

Applications can depend on the `CodexQuotaPetCore` Swift package. Its supported
API, stability policy, and examples are documented in
[docs/CORE_API.md](docs/CORE_API.md). Wire-level examples and synthetic fixtures
are documented in [docs/APP_SERVER_PROTOCOL.md](docs/APP_SERVER_PROTOCOL.md).

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- ChatGPT desktop or Codex CLI signed in with a ChatGPT account
- Swift 6 for source builds and the CLI

See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for the verification matrix.

## Build

```bash
git clone https://github.com/HZGuoo/codex-quota-pet.git
cd codex-quota-pet
Scripts/build-app.sh
open "dist/Codex Quota Pet.app"
```

The build script creates a Universal 2 application in `dist`. Source builds are
ad-hoc signed. Maintainer releases can use Developer ID signing and Apple
notarization. The script currently defaults to SwiftPM's legacy native build
engine because Swift 6.4's default engine fails on some Command Line Tools
installations; set `CODEX_QUOTA_BUILD_SYSTEM=swiftbuild` when the default engine
works locally.

## Verify

```bash
swift run --disable-sandbox CodexQuotaPetSelfTests
```

Optional read-only checks against the current local Codex login:

```bash
swift run --disable-sandbox CodexQuotaPetSelfTests --live
swift run --disable-sandbox CodexQuotaPetSelfTests --dead-proxy
```

## Community and maintenance

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
- Use the issue forms for bugs, compatibility reports, and feature requests.
- Follow current work in [ROADMAP.md](ROADMAP.md).
- See [ADOPTION.md](ADOPTION.md) for verifiable adoption signals.
- Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
- Release history is recorded in [CHANGELOG.md](CHANGELOG.md).

Codex Quota Pet is available under the [MIT License](LICENSE).
