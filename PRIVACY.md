# Privacy

[简体中文](docs/PRIVACY.zh-CN.md)

Codex Quota Pet runs locally. It contains no analytics SDK, advertising SDK,
crash-reporting service, or project-owned backend.

## Data the project reads

- Account type, quota snapshots, and aggregate daily token totals through the
  local `codex app-server` process.
- Minimum task-state and `token_count` metadata written by Codex under
  `~/.codex/sessions` for local status counts and today's aggregate token total.
- Local preferences for proxy mode, refresh interval, window behavior, and the
  selected Codex executable path.

## Data the project does not read or send

- It does not read, copy, persist, or log ChatGPT or Codex authentication tokens.
- Token aggregation does not parse prompt or response text.
- It does not upload task content, quota data, exports, or preferences to a
  server controlled by the project maintainers.
- It does not modify Codex sessions, approve actions, or submit user input.
- It does not silently use a direct connection when an explicit proxy is
  unavailable.

## Network behavior

Quota and usage requests are made by the local Codex child process. When proxy
mode is enabled, Codex receives the selected proxy environment. Connections to
OpenAI remain subject to the service's own terms and privacy policy.

When the user explicitly selects **Check for Updates**, the app sends a normal
HTTPS request to the public GitHub Releases API and reads only the latest tag and
release-page URL. The app does not check automatically in the background.

## Exports

`CodexQuotaPetCore` and `codex-observe` can export JSON or CSV containing quota
windows, aggregate token counts, timestamps, and task-state counts. Exports do
not contain prompts, responses, authentication tokens, proxy credentials, or
complete task identifiers.

## Notifications

A local notification can contain a short title derived from a task's first user
message. Enabling private notification content replaces it with generic status
text. Notifications are managed by macOS Notification Center.

## Deletion

Quitting the app stops the child Codex process. Removing the app preferences
deletes its locally stored settings. Codex account and session data is managed
by Codex or ChatGPT and is outside this application's storage.
