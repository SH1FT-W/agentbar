# AgentBar – Projektregeln

Mac-Menüleisten-App (SwiftUI, Apple Silicon), zeigt laufende Claude-Code-Sitzungen, Kontingent und ein Büro mit
Figuren. Repo SH1FT-W/agentbar, Projektseite https://sh1ft-w.github.io/agentbar/. Allgemeine Regeln (Versionen,
Release-Ablauf, Labels, Fehler beheben): `~/.claude/CLAUDE.md`, hier nur das Repo-Eigene.

- Repo ist **öffentlich**: nichts Persönliches in Code, Commits, Bilder (keine Namen, lokalen Pfade, echten
  Projektnamen, IPs). Vor jedem Release scannen (`git ls-files | grep …`, `strings` auf Bilder).
- README (`README.md` + `README.de.md`), CHANGELOG, RELEASING.md, Release-Notizen und Commit-Texte auf Englisch.
  Oberfläche zweisprachig über `L("de","en")`; Code-Kommentare englisch (bestehende deutsche nur bei Änderungen an der
  Datei mit übersetzen).
- **Screenshots nur mit Demo-Daten:** Büro aus `tools/snapshot.swift`, Menü/Einstellungen aus
  `tools/snapshot_menu.swift`, je Sprache per `AGENTBAR_LANG=de|en` nach `docs/screenshots/{de,en}/`.
  `./build.sh snapshot`-Menübilder zeigen echte Sitzungen: nie veröffentlichen.
- Lokal committen ok; installieren, pushen und releasen nur nach Rückfrage.
- Gemeinsamer Code (Updater, Menü-Bausteine, Sprache, Bau-Werkzeuge) liegt in `Shared/` als subtree von
  SH1FT-W/swift-shared: dort ändern (`tools/check.sh`), dann `git subtree pull` (siehe RELEASING.md), nie direkt in
  `Shared/` oder als Kopie in `Sources/`.
- Kontingent über den Schlüsselbund-Eintrag von Claude Code: den Token **nie erneuern** (würde Claude Codes
  Refresh-Token gefährden).

## Bauen und prüfen
- Ohne Xcode: swiftc gegen das macOS-26.5-SDK der Command Line Tools (SDK 27 scheitert am SwiftUI-Macro-Plugin).
- `./build.sh` → `build/AgentBar.app`, `./build.sh install` → nach `/Applications` und neu starten.
- `./build.sh test` = Selbsttests (`tools/selftest.swift`), läuft auch in `.github/workflows/build.yml`.
- Optik: `./build.sh snapshot` / `build/snapshot --festive|--weather|--coffee|--seasons|--moments` (Fake-Datum/-Wetter
  per `AGENTBAR_FAKE_DATE` / `AGENTBAR_FAKE_WEATHER`); Glas ist offscreen nicht sichtbar (`snapshot_menu --flat`).
- Diagnose: `AgentBar --dump` (`AGENTBAR_DEBUG=1`).

## Release
- `./build.sh release next "What's new"` (RELEASING.md): Selbsttests, Bau, Commit von Info.plist, Tag, Push,
  GitHub-Release mit `AgentBar.zip` + `.sha256` + `.sig`. Bricht bei unsauberem Arbeitsbaum ab, Fixes also vorher
  committen. Tags ohne „v“ seit 26.11.1 (ältere `v`-Tags zählen mit).
- Ed25519-Schlüssel nur lokal in `~/Library/Application Support/AgentBar Release/`, nie ins Repo.
- Vorher: Screenshots in `docs/` passen noch, „New in …“-Zeile in beiden READMEs, CHANGELOG `## Unreleased` zur
  Versionsnummer, Datenschutz-Scan.

## Pflege
- Monatliche Fix-Runde mit dem HA-Beta-Check: Worktree `agentbar-fixrunde`, Zweig `fixrunde-YYYY-MM`. Ablauf:
  installierte Version + CPU/RAM prüfen, Build-Warnungen, Code/Sicherheit und Bedienung/Design sichten, Funde selbst
  nachprüfen, Fixes + `./build.sh test` + Snapshots, lokal committen, Release erst nach OK.
