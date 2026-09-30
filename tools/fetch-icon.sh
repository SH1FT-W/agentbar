#!/bin/zsh
# Holt das von GitHub Actions kompilierte Icon (Workflow „App-Icon“) nach Resources/:
# Assets.car (Hell/Dunkel/Klar/Getönt) + AppIcon.icns (Rückfall); partial.plist nach build/icon-preview/.
# Vorher: swift tools/make-icon.swift, AppIcon.icon committen + pushen.
set -e
cd "$(dirname "$0")/.."
REPO=SH1FT-W/agentbar
SHA=$(git rev-parse HEAD)
echo "Warte auf Icon-Build für ${SHA:0:7} …"
for i in {1..60}; do
    RUN=$(gh run list -R $REPO -w App-Icon --commit "$SHA" --json databaseId,status -q '.[0] | select(.status=="completed") | .databaseId')
    [[ -n "$RUN" ]] && break
    sleep 10
done
[[ -n "$RUN" ]] || { echo "Kein fertiger Lauf – gh run list -R $REPO -w App-Icon"; exit 1; }
rm -rf build/icon-preview; mkdir -p build/icon-preview
gh run download "$RUN" -R $REPO -n app-icon -D build/icon-preview
mv build/icon-preview/Assets.car build/icon-preview/AppIcon.icns Resources/
echo "Fertig: Resources/Assets.car + AppIcon.icns"
