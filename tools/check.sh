#!/bin/zsh
# Type checks the shared sources on their own, with the AppConfig template standing in for an app.
# The apps compile the real thing; this only catches mistakes before pushing.
set -e
cd "$(dirname "$0")/.."
if [[ -z "$SDK" ]]; then
    SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | grep -v 'MacOSX26.sdk$' | sort -V | tail -1)
    [[ -z "$SDK" ]] && SDK=$(xcrun --sdk macosx --show-sdk-path)
fi
swiftc -typecheck -swift-version 5 -parse-as-library -sdk "$SDK" -target arm64-apple-macos14 Sources/*.swift tools/AppConfig.swift
swiftc -typecheck -swift-version 5 -parse-as-library -D SNAPSHOT -sdk "$SDK" -target arm64-apple-macos14 Sources/*.swift tools/AppConfig.swift
swiftc -typecheck -sdk "$SDK" -target arm64-apple-macos14 tools/release-key.swift
bash -n tools/next-version
zsh -n tools/build-common.sh tools/fetch-icon.sh
echo "OK"
