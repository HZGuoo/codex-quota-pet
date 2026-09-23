# Release signing, notarization, and Homebrew

Tagged GitHub releases use Developer ID signing and Apple notarization when all
five repository secrets below are configured. Without them, the workflow keeps
the existing ad-hoc-signed fallback and says so in the release notes.

## Required GitHub Actions secrets

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_API_KEY_BASE64` | Base64-encoded App Store Connect `AuthKey_*.p8` |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |

The workflow imports credentials into a temporary keychain, signs the app with
the hardened runtime, submits a temporary ZIP to Apple, staples the ticket to
the app, verifies it, and packages the final Universal 2 ZIP.

## Local notarized package

```bash
export APPLE_DEVELOPER_ID="Developer ID Application: Example (TEAMID)"
export APPLE_API_KEY_ID="KEYID"
export APPLE_API_ISSUER_ID="ISSUER-UUID"
export APPLE_API_KEY_FILE="$HOME/private_keys/AuthKey_KEYID.p8"
Scripts/package-notarized-release.sh
```

Do not commit certificates, API keys, or keychain exports.

## Homebrew Cask

`Casks/codex-quota-pet.rb` describes the current release. Before publishing a
new tag, update its `version` and replace `sha256` with the checksum from the
new release artifact. The cask can be tested from a checkout with:

```bash
brew install --cask ./Casks/codex-quota-pet.rb
brew uninstall --cask codex-quota-pet
```

For a one-command public install, copy the validated cask into a public Homebrew
tap such as `HZGuoo/homebrew-tap`. That external tap does not exist in this
repository and must not be advertised until it is published.
