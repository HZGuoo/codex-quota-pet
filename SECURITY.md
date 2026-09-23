# Security Policy

[简体中文](docs/SECURITY.zh-CN.md)

## Supported versions

Security fixes target the latest release and the `main` branch. Older releases
may need to upgrade before receiving a fix.

## Report a vulnerability

Do not open a public issue for an unpatched vulnerability. Use GitHub
**Security → Report a vulnerability** and include:

- affected Codex Quota Pet and macOS versions;
- minimal reproduction steps and expected impact;
- the smallest necessary redacted log or screenshot;
- a suggested mitigation, if available.

Remove tokens, email addresses, proxy credentials, complete prompts or
responses, private paths, and other personal data. The maintainer will confirm
receipt, assess impact, and coordinate disclosure after a fix is available.

## Security boundary

The project launches the local `codex app-server`, reads minimum task-state and
usage metadata written by Codex, and can configure a proxy for the child
process. It must not read, copy, persist, or log authentication tokens. It must
also fail closed instead of bypassing an explicitly configured proxy. Regressions
in these boundaries should be reported as security issues.
