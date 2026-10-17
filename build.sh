#!/bin/zsh
# Baut AgentBar.app (Apple Silicon). Die gemeinsamen Schritte liegen in Shared/tools/build-common.sh.
#   ./build.sh            → build/AgentBar.app
#   ./build.sh install    → zusätzlich nach /Applications und neu starten
#   ./build.sh test       → Selbsttests (tools/selftest.swift), baut keine App
#   ./build.sh snapshot   → Dropdown + Büro als PNG nach build/ (ohne Menüleiste)
#   ./build.sh release next ["Was ist neu"]
#                         → Version setzen, bauen, committen, taggen, pushen und als GitHub-Release
#                           (AgentBar.zip + .sha256 + .sig) in SH1FT-W/agentbar veröffentlichen; die App holt es per Update-Button
#                         Versionen = Kalender-Versionen YY.M.N (Shared/tools/next-version); jedes Release ist die nächste Nummer im Monat
set -e
cd "$(dirname "$0")"

APP=AgentBar
BUNDLE_ID=io.github.sh1ft-w.agentbar
REPO=SH1FT-W/agentbar
# Öffentlicher Release-Schlüssel aus dem Updater; der private liegt nur lokal (Shared/tools/release-key.swift)
SIGN_KEY=$(grep -o 'publicKey = "[^"]*"' Sources/Updater.swift | cut -d'"' -f2)
[[ -n "$SIGN_KEY" ]] || { echo "Updater.publicKey nicht gefunden."; exit 1; }
source Shared/tools/build-common.sh

case "$1" in
    release) release_prepare "$2" ;;
    test) build_test ;;
    snapshot) build_tool snapshot tools/snapshot.swift; build/snapshot "${@:2}"; exit 0 ;;
esac

build_app

[[ "$1" == "install" ]] && install_app
[[ "$1" == "release" ]] && release_publish "$3"
exit 0
