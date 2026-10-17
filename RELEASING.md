# Releasing

`./build.sh release next "What's new"` sets the version, runs the self tests, builds, commits, tags, pushes and publishes `AgentBar.zip`, `AgentBar.zip.sha256` and `AgentBar.zip.sig` as a GitHub release in `SH1FT-W/agentbar`. Installed apps pick it up through their update check ("Check for Updates" in the menu). Release notes are public, so write them in English.

Versions are calendar versions `YY.M.N`: two-digit year, month without a leading zero, and the running number of the release within that month, starting at 1 (every GitHub release published that month counts, including older `X.Y.Z` ones; bare tags without a release do not). A new month starts again at `.1`. `tools/next-version --prefix v` computes the next one (tag `vYY.M.N`); `next` uses it, and any other version is refused unless `ALLOW_VERSION=1` is set. Version checks compare the numbers part by part, so `26.10.11` is newer than `26.10.9` and any calendar version is newer than `2.x`.

## Signing

The update button installs a release only if its Ed25519 signature matches `Updater.publicKey` in `Sources/Updater.swift`. `build.sh release` signs `AgentBar.zip` with the private key from the local keychain (`tools/release-key.swift`), which never lives in the repo. If the public key printed by `build/release-key public` does not match `Updater.publicKey`, the release is aborted.

## Before a release

- `./build.sh test` is green (the release script runs it as well).
- The office and menu screenshots in `docs/` still match the app.
- The "What's new" table in `README.md` and `README.de.md` mentions the release.
