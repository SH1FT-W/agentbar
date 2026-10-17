#!/bin/zsh
# Fetches the icon compiled by GitHub Actions (workflow "App-Icon", see tools/icon.yml) into Resources/:
# Assets.car (light/dark/clear/tinted) + AppIcon.icns (fallback); partial.plist goes to build/icon-preview/.
# Before: swift tools/make-icon.swift, commit and push AppIcon.icon.
#   Usage: Shared/tools/fetch-icon.sh [OWNER/REPO]   (default: the origin remote of the current repo)
set -e
cd "$(git rev-parse --show-toplevel)"
REPO=${1:-$(git remote get-url origin | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')}
SHA=$(git rev-parse HEAD)
echo "Waiting for the icon build of ${SHA:0:7} in $REPO ..."
for i in {1..60}; do
    RUN=$(gh run list -R "$REPO" -w App-Icon --commit "$SHA" --json databaseId,status -q '.[0] | select(.status=="completed") | .databaseId')
    [[ -n "$RUN" ]] && break
    sleep 10
done
[[ -n "$RUN" ]] || { echo "No finished run. Check: gh run list -R $REPO -w App-Icon"; exit 1; }
rm -rf build/icon-preview; mkdir -p build/icon-preview
gh run download "$RUN" -R "$REPO" -n app-icon -D build/icon-preview
mv build/icon-preview/Assets.car build/icon-preview/AppIcon.icns Resources/
echo "Done: Resources/Assets.car + AppIcon.icns"
