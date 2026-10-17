# Shared build steps for the SH1FT-W menu bar apps. Not a program: the app's build.sh sets the
# variables below and sources this file, then calls the functions it needs.
#
#   APP        app name: APP.app, the executable and APP.zip in releases
#   BUNDLE_ID  bundle identifier, checked against Info.plist
#   REPO       GitHub slug (OWNER/NAME) that receives the releases
#   SIGN_KEY   Ed25519 public key (Base64) when releases are signed with tools/release-key.swift,
#              empty when the checksum is enough
#   OUT        release folder (default build/release)
#   TEST       self test driver (default tools/selftest.swift)
#
#   release_prepare VERSION   checks and sets the version in Info.plist (first step of "release")
#   build_test                compiles the sources + TEST with -D SNAPSHOT and runs it (never returns)
#   build_tool NAME FILE      compiles the sources + FILE with -D SNAPSHOT to build/NAME
#   build_app                 builds build/APP.app: Info.plist, resources, swiftc -O, ad hoc signature
#   install_app               copies build/APP.app to /Applications and opens it
#   release_publish [NOTES]   zip, checksum, optional signature, commit, tag, push, GitHub release
#
# Sources: Sources/*.swift plus Shared/Sources/*.swift (this repository as a git subtree).
# SDK: prefers a macOS 26 SDK of the Command Line Tools (SDK 27 needs the SwiftUI macro plugin that
# only Xcode ships); otherwise the default SDK. Override with SDK=/path/to/sdk.

: "${APP:?APP is not set}" "${BUNDLE_ID:?BUNDLE_ID is not set}" "${REPO:?REPO is not set}"
OUT=${OUT:-build/release}
TEST=${TEST:-tools/selftest.swift}
SOURCES=(Sources/*.swift Shared/Sources/*.swift)
TARGET=arm64-apple-macos14

if [[ -z "$SDK" ]]; then
    SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | grep -v 'MacOSX26.sdk$' | sort -V | tail -1)
    [[ -z "$SDK" ]] && SDK=$(xcrun --sdk macosx --show-sdk-path)
fi

# Calendar version YY.M.N (running number within the month): "next" or nothing = tools/next-version.
release_prepare() {
    VERSION="$1"
    local next
    next=$(Shared/tools/next-version) || { echo "Shared/tools/next-version failed."; exit 1; }
    [[ -z "$VERSION" || "$VERSION" == "next" ]] && VERSION="$next"
    [[ "$VERSION" =~ '^[0-9]+(\.[0-9]+)+$' ]] || { echo "Usage: ./build.sh release next [\"What's new\"]"; exit 1; }
    [[ "$VERSION" == "$next" || -n "$ALLOW_VERSION" ]] || { echo "Next calendar version is $next (YY.M.N), not $VERSION. On purpose: ALLOW_VERSION=1 ./build.sh release ..."; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo "Commit everything first, the working tree is not clean."; exit 1; }
    git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "Tag v$VERSION exists already."; exit 1; }
    ./build.sh test || { echo "Self tests failed, no release."; exit 1; }
    local build=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist) + 1 ))
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $build" Info.plist
}

build_tool() {
    mkdir -p build
    swiftc -swift-version 5 -parse-as-library -D SNAPSHOT -sdk "$SDK" -target $TARGET \
        "${SOURCES[@]}" "$2" -o "build/$1"
}

build_test() {
    build_tool selftest "$TEST"
    exec build/selftest
}

build_app() {
    local bundle=build/$APP.app
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)" == "$BUNDLE_ID" ]] \
        || { echo "Info.plist has a different bundle identifier than BUNDLE_ID ($BUNDLE_ID)."; exit 1; }
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
    cp Info.plist "$bundle/Contents/Info.plist"
    [[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$bundle/Contents/Resources/"
    # Assets.car = Icon Composer icon with light/dark/clear/tinted (tools/fetch-icon.sh); AppIcon.icns stays as fallback
    [[ -f Resources/Assets.car ]] && cp Resources/Assets.car "$bundle/Contents/Resources/"
    # Language folders (InfoPlist.strings); UI texts live in the sources (L(de, en))
    for lproj in Resources/*.lproj(N); do cp -R "$lproj" "$bundle/Contents/Resources/"; done
    swiftc -O -swift-version 5 -parse-as-library -sdk "$SDK" -target $TARGET \
        "${SOURCES[@]}" -o "$bundle/Contents/MacOS/$APP"
    # Ad hoc signature (no certificate); the keychain asks once after an update
    codesign --force --sign - "$bundle"
    echo "Built: $bundle ($(lipo -archs "$bundle/Contents/MacOS/$APP"))"
}

install_app() {
    pkill -x "$APP" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP.app"
    cp -R "build/$APP.app" /Applications/
    open "/Applications/$APP.app"
    echo "Installed: /Applications/$APP.app"
}

release_publish() {
    local notes="$1"
    rm -rf "$OUT"; mkdir -p "$OUT"
    ditto -c -k --keepParent "build/$APP.app" "$OUT/$APP.zip"
    (cd "$OUT" && shasum -a 256 "$APP.zip" > "$APP.zip.sha256")
    local assets=("$OUT/$APP.zip" "$OUT/$APP.zip.sha256")
    if [[ -n "$SIGN_KEY" ]]; then
        # Ed25519 signature for the update button (private key only local, see tools/release-key.swift)
        swiftc -sdk "$SDK" -target $TARGET Shared/tools/release-key.swift -o build/release-key
        [[ "$(build/release-key "$APP" public)" == "$SIGN_KEY" ]] \
            || { echo "The release key does not match SIGN_KEY (the app's publicKey). Aborted."; exit 1; }
        build/release-key "$APP" sign "$OUT/$APP.zip" > "$OUT/$APP.zip.sig"
        assets+=("$OUT/$APP.zip.sig")
    fi
    git add Info.plist
    git commit -q -m "v$VERSION"
    git tag "v$VERSION"
    git push -q origin HEAD "v$VERSION"
    # Release notes are public: write them in English
    if [[ -n "$notes" ]]; then
        gh release create "v$VERSION" "${assets[@]}" --repo "$REPO" --title "v$VERSION" --notes "$notes"
    else
        gh release create "v$VERSION" "${assets[@]}" --repo "$REPO" --title "v$VERSION" --generate-notes
    fi
    echo "Release v$VERSION published. In the app: Check for Updates."
}
