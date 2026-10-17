# swift-shared

Code that the SH1FT-W menu bar apps ([AgentBar](https://github.com/SH1FT-W/agentbar) and [ShareMount](https://github.com/SH1FT-W/sharemount)) have in common. No package, no framework: the apps pull this repository in as a git subtree under `Shared/` and compile `Shared/Sources/*.swift` together with their own sources.

## Sources

| File | What it holds |
|:--|:--|
| `Lang.swift` | `L(de, en)` and `Lang.isGerman`, following the system language, overridable through the variable named by `AppConfig.langEnvVar`. Declares the `SharedAppConfig` protocol the app's `AppConfig` adopts. |
| `MenuComponents.swift` | The menu building blocks in the style of the macOS 26/27 system menus: `MenuMetrics`, `cardShape`, `glassButton` / `glassProminentButton` / `glassCircleButton`, `SectionHeader`, `MenuSeparator`, `MenuItem`. The remaining differences between the apps are a `MenuLook` set once at the menu root with `.menuLook(_:)`. |
| `UpdateCore.swift` | The steps of a GitHub Releases updater: `GitHubRelease` (parsing, asset links), `UpdateCore.fetchLatestRelease`, `download` (token only to api.github.com, dropped on redirect), `isNewer`, `verifyChecksum`, `verifyEd25519`, `targetProblem`, `unpackAndVerify` (bundle ID, version, code signature, quarantine removed only afterwards), `launchSwapScript` (`zsh -f`, static script, paths as arguments), and `ReleaseNotes` (plain text and Markdown). Repository, app name, bundle ID, public key and surrounding texts are parameters. |
| `UpdatePromptKit.swift` | The frame of the "new version" window: `UpdateWindow.style`, `UpdatePromptFrame`, `UpdatePromptHeading`, `UpdateNotesBox`. The app keeps its own controller and the state dependent content. |

The app declares `enum AppConfig: SharedAppConfig` in its own sources (template: `tools/AppConfig.swift`). Everything is compiled as one module, so the shared code can refer to it by name.

## Tools

| File | What it does |
|:--|:--|
| `build-common.sh` | Sourced by the app's `build.sh` after setting `APP`, `BUNDLE_ID`, `REPO`, `SIGN_KEY` (and optionally `OUT`, `TEST`). Provides `release_prepare`, `build_test`, `build_tool`, `build_app`, `install_app`, `release_publish`. |
| `next-version` | Next calendar version `YY.M.N` from the published GitHub releases of the month. |
| `release-key.swift` | Ed25519 key for signed releases: `release-key <App> generate | public | sign <file>`. The private key stays in `~/Library/Application Support/<App> Release/`. |
| `fetch-icon.sh` | Downloads the icon compiled by the `App-Icon` workflow into `Resources/`. |
| `icon.yml` | The `App-Icon` workflow (Icon Composer `.icon` to `Assets.car` + `AppIcon.icns` with `actool`). Copy to `.github/workflows/`. |
| `AppConfig.swift` | Template for the app's `AppConfig`. |
| `check.sh` | Type checks the shared sources with the template in place of an app. |

## Using it in an app

```sh
# once
git subtree add --prefix=Shared https://github.com/SH1FT-W/swift-shared.git main --squash
# update to the latest shared code
git subtree pull --prefix=Shared https://github.com/SH1FT-W/swift-shared.git main --squash
# give a change made inside the app's Shared/ back to this repository
git subtree push --prefix=Shared https://github.com/SH1FT-W/swift-shared.git main
```

The repository is private; pulling and pushing need a GitHub account with access (`gh auth login`). Behaviour and look of the apps must not change through a shared update unless the app asks for it: anything app specific stays a parameter.

## License

Private project, all rights reserved. The copies that live inside the public apps are covered by the respective app's license.
