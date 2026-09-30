#!/bin/zsh
# Baut AgentBar.app (Apple Silicon).
#   ./build.sh            → build/AgentBar.app
#   ./build.sh install    → zusätzlich nach /Applications und neu starten
#   ./build.sh snapshot   → Dropdown + Büro als PNG nach build/ (ohne Menüleiste)
#   ./build.sh release 1.1 ["Was ist neu"]
#                         → Version setzen, bauen, committen, taggen, pushen und als GitHub-Release
#                           (AgentBar.zip + .sha256) in SH1FT-W/agentbar veröffentlichen – die App holt es per Update-Button
set -e
cd "$(dirname "$0")"

if [[ "$1" == "release" ]]; then
    VERSION="$2"
    [[ "$VERSION" =~ '^[0-9]+(\.[0-9]+)+$' ]] || { echo "Aufruf: ./build.sh release 1.1 [\"Was ist neu\"]"; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo "Erst alles committen – Arbeitsverzeichnis ist nicht sauber."; exit 1; }
    git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "Tag v$VERSION gibt es schon."; exit 1; }
    BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist) + 1 ))
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" Info.plist
fi
# SDK wählen: mit reinen CommandLineTools fehlt dem SDK 27 das SwiftUI-Macro-Plugin → ein 26er-SDK bevorzugen.
# Mit installiertem Xcode (oder ohne 26er-SDK) das Standard-SDK nehmen. Überschreibbar: SDK=/pfad ./build.sh
if [[ -z "$SDK" ]]; then
    SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | grep -v 'MacOSX26.sdk$' | sort -V | tail -1)
    [[ -z "$SDK" ]] && SDK=$(xcrun --show-sdk-path)
fi

if [[ "$1" == "snapshot" ]]; then
    mkdir -p build
    swiftc -swift-version 5 -parse-as-library -D SNAPSHOT -sdk "$SDK" -target arm64-apple-macos14 \
        Sources/*.swift tools/snapshot.swift -o build/snapshot
    build/snapshot "${@:2}"
    exit 0
fi

APP=build/AgentBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Assets.car = Icon-Composer-Icon mit Hell/Dunkel/Klar/Getönt (tools/fetch-icon.sh); AppIcon.icns bleibt Rückfall
[[ -f Resources/Assets.car ]] && cp Resources/Assets.car "$APP/Contents/Resources/"
# Sprachordner (InfoPlist.strings, z. B. für NSAppleEventsUsageDescription) – Oberflächentexte stehen in Sources/Lang.swift
for lproj in Resources/*.lproj(N); do cp -R "$lproj" "$APP/Contents/Resources/"; done
swiftc -O -swift-version 5 -parse-as-library -sdk "$SDK" -target arm64-apple-macos14 \
    Sources/*.swift -o "$APP/Contents/MacOS/AgentBar"
codesign --force --sign - "$APP"
echo "Gebaut: $APP"

if [[ "$1" == "install" ]]; then
    pkill -x AgentBar 2>/dev/null || true
    sleep 1
    rm -rf /Applications/AgentBar.app
    cp -R "$APP" /Applications/
    open /Applications/AgentBar.app
    echo "Installiert: /Applications/AgentBar.app"
fi

if [[ "$1" == "release" ]]; then
    OUT=build/release
    rm -rf "$OUT"; mkdir -p "$OUT"
    ditto -c -k --keepParent "$APP" "$OUT/AgentBar.zip"
    (cd "$OUT" && shasum -a 256 AgentBar.zip > AgentBar.zip.sha256)
    # Ed25519-Signatur für den Update-Button (privater Schlüssel nur lokal, siehe tools/release-key.swift)
    swiftc -sdk "$SDK" -target arm64-apple-macos14 tools/release-key.swift -o build/release-key
    [[ "$(build/release-key public)" == "$(grep -o 'publicKey = "[^"]*"' Sources/Updater.swift | cut -d'"' -f2)" ]] \
        || { echo "Release-Schlüssel passt nicht zu Updater.publicKey – abgebrochen."; exit 1; }
    build/release-key sign "$OUT/AgentBar.zip" > "$OUT/AgentBar.zip.sig"
    git add Info.plist
    git commit -q -m "v$VERSION"
    git tag "v$VERSION"
    git push -q origin HEAD "v$VERSION"
    # Release-Notizen bitte auf Englisch (öffentliches Repo)
    gh release create "v$VERSION" "$OUT/AgentBar.zip" "$OUT/AgentBar.zip.sha256" "$OUT/AgentBar.zip.sig" \
        --repo SH1FT-W/agentbar --title "v$VERSION" --notes "${3:-v$VERSION}"
    echo "Release v$VERSION veröffentlicht – in der App: „Nach Updates suchen“"
fi
