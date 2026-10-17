# Releasing

`./build.sh release next "What's new"` sets the version, runs the self tests, builds, commits, tags, pushes and publishes `AgentBar.zip`, `AgentBar.zip.sha256` and `AgentBar.zip.sig` as a GitHub release in `SH1FT-W/agentbar`. Installed apps pick it up through their update check ("Check for Updates" in the menu). Release notes are public, so write them in English.

Versions are calendar versions `YY.M.N`: two-digit year, month without a leading zero, and the running number of the release within that month, starting at 1 (every GitHub release published that month counts, including older `X.Y.Z` ones; bare tags without a release do not). A new month starts again at `.1`. `Shared/tools/next-version --prefix v` computes the next one (tag `vYY.M.N`); `next` uses it, and any other version is refused unless `ALLOW_VERSION=1` is set. Version checks compare the numbers part by part, so `26.10.11` is newer than `26.10.9` and any calendar version is newer than `2.x`.

## Signing

The update button installs a release only if its Ed25519 signature matches `Updater.publicKey` in `Sources/Updater.swift`. `build.sh release` signs `AgentBar.zip` with the private key from `~/Library/Application Support/AgentBar Release/` (`Shared/tools/release-key.swift`, called as `release-key AgentBar ...`), which never lives in the repo. If the public key printed by `build/release-key AgentBar public` does not match `SIGN_KEY` (read from `Updater.publicKey` in `build.sh`), the release is aborted.

## Shared code

`Shared/` is a git subtree of the private repository `SH1FT-W/swift-shared`: language helper, menu components, the updater core, the update window kit and the build tooling that AgentBar and ShareMount have in common. `build.sh` compiles `Shared/Sources/*.swift` together with `Sources/*.swift` and sources `Shared/tools/build-common.sh`. Pulling and pushing need a GitHub account with access to that repository (`gh auth status`).

```sh
# take the latest shared code
git subtree pull --prefix=Shared https://github.com/SH1FT-W/swift-shared.git main --squash
# give a change made in Shared/ back to the shared repository
git subtree push --prefix=Shared https://github.com/SH1FT-W/swift-shared.git main
```

Both need a clean working tree. After a pull, build, run the tests and compare the snapshots (`./build.sh snapshot`) before releasing: shared changes must not alter AgentBar's behaviour or look unless intended.

## Before a release

- `./build.sh test` is green (the release script runs it as well).
- The office and menu screenshots in `docs/` still match the app.
- The "What's new" table in `README.md` and `README.de.md` mentions the release.
