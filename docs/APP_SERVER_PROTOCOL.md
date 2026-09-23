# Codex App Server integration

Codex Quota Pet launches the locally installed `codex app-server` process and
communicates over newline-delimited JSON on standard input and output. It does
not copy authentication credentials into the application.

The App Server evolves with Codex. Consumers should use the typed
`CodexAppServerClient` API instead of depending directly on the wire examples
below, and should consult `COMPATIBILITY.md` before upgrading Codex.

## Session initialization

Request:

```json
{"id":1,"method":"initialize","params":{"clientInfo":{"name":"my_tool","title":"My Tool","version":"0.1.0"}}}
```

After a successful response, send:

```json
{"method":"initialized","params":{}}
```

## Requests used by this project

| Method | Purpose | Exported data |
| --- | --- | --- |
| `account/read` | Identify the account type and plan | Account type only |
| `account/rateLimits/read` | Read quota windows and reset times | Aggregate quota metadata |
| `account/usage/read` | Read daily token totals | Aggregate daily totals |
| `thread/list` | Reconcile active top-level task states | Counts by state |

The project also listens for App Server notifications and reads minimum event
metadata from local rollout files when a separate desktop App Server process
makes notifications unavailable.

## Example response payloads

Versioned examples live in [`Fixtures/app-server`](../Fixtures/app-server).
They intentionally contain synthetic identifiers and values. Add a sanitized
fixture and parser regression test whenever a Codex version changes a response
shape.

## Compatibility rules

1. Treat missing optional fields as a supported older response shape.
2. Prefer duration metadata over positional assumptions for quota windows.
3. Ignore unknown notification fields unless they change a documented state.
4. Never log raw server lines. Error logging removes lines that may contain
   authorization or token data.
5. Fail closed when an explicitly configured proxy is unreachable.
