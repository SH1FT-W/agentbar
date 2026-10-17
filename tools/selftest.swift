// Kleine Selbsttests ohne Xcode: ./build.sh test
// Nur reine Logik (Versionen, Code, Deko-Kalender, Hook-Parser, Werkzeugtexte, Preise, Zeitstempel), nichts mit Oberfläche.
import Foundation

@main
struct SelfTest {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ ok: Bool, _ what: String, line: Int = #line) {
        if ok { print("  ✓ \(what)") } else { failures += 1; print("  ✗ \(what) (Zeile \(line))") }
    }

    /// Fester Kalender, damit die Deko-Tests nicht von Zeitzone oder Systemkalender abhängen.
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func festive(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Festive {
        Festive.compute(date(y, m, d, h, min), cal: cal)
    }

    @MainActor static func main() {
        print("Versionen")
        expect(Updater.isNewer("2.0", than: "1.7"), "2.0 > 1.7")
        expect(Updater.isNewer("1.10", than: "1.9"), "1.10 > 1.9")
        expect(!Updater.isNewer("1.7", than: "1.7.0"), "1.7 = 1.7.0")
        expect(!Updater.isNewer("1.6.9", than: "1.7"), "1.6.9 < 1.7")
        expect(Updater.isNewer("26.10.11", than: "2.3.1"), "Kalender-Version 26.10.11 > 2.3.1")
        expect(Updater.isNewer("26.10.10", than: "26.10.9"), "26.10.10 > 26.10.9")
        expect(!Updater.isNewer("26.10.9", than: "26.10.10"), "26.10.9 < 26.10.10")
        expect(Updater.isNewer("26.11.1", than: "26.10.12"), "26.11.1 > 26.10.12")
        expect(Updater.isNewer("27.1.1", than: "26.12.30"), "27.1.1 > 26.12.30")
        expect(!Updater.isNewer("26.10.11", than: "26.10.11"), "gleiche Version ist nicht neuer")

        print("Kopplungscode")
        expect(PeerCode.normalize("abcd-efgh-jkmn") == "ABCD-EFGH-JKMN", "Kleinbuchstaben und Bindestriche")
        expect(PeerCode.normalize(" abcd efgh jkmn ") == "ABCD-EFGH-JKMN", "Leerzeichen")
        expect(PeerCode.normalize("ABCDEFGHJKMN") == "ABCD-EFGH-JKMN", "ohne Trenner → gruppiert")
        expect(PeerCode.normalize("ABCD-EFGH-JKMI") == nil, "I ist nicht im Alphabet")
        expect(PeerCode.normalize("ABCD-EFGH-JKM0") == nil, "0 ist nicht im Alphabet")
        expect(PeerCode.normalize("ABCD-EFGH-JKM") == nil, "11 Zeichen → ungültig")
        expect(PeerCode.normalize("ABCD-EFGH-JKMNP") == nil, "13 Zeichen → ungültig")
        expect(PeerCode.normalize("") == nil, "leer → ungültig")
        let code = PeerCode.generate()
        expect(code.count == 14 && PeerCode.normalize(code) == code, "generate() liefert gültigen Code (\(code))")
        expect(PeerCode.generate() != code, "zwei Codes sind verschieden")

        print("Deko-Kalender: Advent und Weihnachten")
        expect(cal.component(.day, from: Festive.firstAdvent(year: 2026, cal: cal)) == 29
               && cal.component(.month, from: Festive.firstAdvent(year: 2026, cal: cal)) == 11, "1. Advent 2026 = 29.11.")
        expect(cal.component(.day, from: Festive.firstAdvent(year: 2027, cal: cal)) == 28, "1. Advent 2027 = 28.11.")
        expect(cal.component(.day, from: Festive.firstAdvent(year: 2022, cal: cal)) == 27, "1. Advent 2022 = 27.11. (Weihnachten am Sonntag)")
        expect(festive(2026, 11, 28) == Festive.none, "Tag vor dem 1. Advent: keine Deko")
        var f = festive(2026, 11, 29)
        expect(f.wreath && f.candles == 1 && f.stars && !f.lights && !f.tree && f.gifts == 0, "1. Advent: Kranz, 1 Kerze, Sterne")
        expect(f.outfitTheme == .christmas && f.outfitChance == 0.25, "1. Advent: wenige Weihnachtsoutfits")
        f = festive(2026, 12, 6)
        expect(f.candles == 2 && f.lights && !f.tree && f.boots, "2. Advent am 6.12.: 2 Kerzen, Lichterkette, Stiefel")
        expect(!festive(2026, 12, 5).boots && !festive(2026, 12, 7).boots, "Stiefel nur am 6.12.")
        f = festive(2026, 12, 13)
        expect(f.candles == 3 && f.tree && f.gifts == 0, "3. Advent: Baum, noch keine Geschenke")
        f = festive(2026, 12, 20)
        expect(f.candles == 4 && f.gifts == 2, "4. Advent: 4 Kerzen, erste Geschenke")
        f = festive(2026, 12, 24)
        expect(f.gifts == 6 && f.wreath && f.vacuumHat && f.outfitChance == 0.85, "Heiligabend: alle Geschenke, Mütze auf dem Sauger")
        f = festive(2026, 12, 27)
        expect(!f.wreath && f.candles == 0 && f.tree && f.lights && f.gifts == 0 && f.outfitChance == 0.3, "27.12.: Kranz weg, Baum bleibt")
        f = festive(2027, 1, 6)
        expect(f.stars && f.tree && f.lights && !f.wreath, "Heilige Drei Könige: letzter Tag mit Baum")
        expect(festive(2027, 1, 7) == Festive.none, "7.1.: alles abgebaut")

        print("Deko-Kalender: Silvester und Neujahr")
        f = festive(2026, 12, 31, 17)
        expect(f.bunting && f.fireworks == 0 && f.outfitTheme == .newYear && f.outfitChance == 0.45, "Silvester nachmittags: Wimpel, kein Feuerwerk")
        expect(festive(2026, 12, 31, 18).fireworks == 0.15, "Silvester ab 18 Uhr: vereinzelt Feuerwerk")
        expect(festive(2026, 12, 31, 23, 50).fireworks == 1, "Silvester 23:50: Feuerwerk")
        f = festive(2027, 1, 1, 0, 30)
        expect(f.fireworks == 1 && f.confetti && f.bunting, "Neujahr 0:30: Feuerwerk, Konfetti, Wimpel")
        expect(festive(2027, 1, 1, 1, 30).fireworks == 0.3, "Neujahr 1:30: Feuerwerk klingt ab")
        f = festive(2027, 1, 1, 13)
        expect(!f.bunting && f.confetti && f.fireworks == 0 && f.outfitTheme == .none, "Neujahr 13 Uhr: nur noch Konfetti")
        expect(!festive(2027, 1, 1, 16).confetti, "Neujahr 16 Uhr: aufgeräumt")
        expect(!festive(2026, 12, 30).bunting, "30.12.: noch keine Wimpel")

        print("Deko-Kalender: Ostern, Halloween, Valentinstag")
        expect(cal.dateComponents([.month, .day], from: Festive.easterSunday(year: 2026, cal: cal)) == DateComponents(month: 4, day: 5), "Ostersonntag 2026 = 5.4.")
        expect(cal.dateComponents([.month, .day], from: Festive.easterSunday(year: 2027, cal: cal)) == DateComponents(month: 3, day: 28), "Ostersonntag 2027 = 28.3.")
        expect(cal.dateComponents([.month, .day], from: Festive.easterSunday(year: 2024, cal: cal)) == DateComponents(month: 3, day: 31), "Ostersonntag 2024 = 31.3.")
        expect(festive(2026, 3, 28).easter == 0, "Samstag vor Palmsonntag: nichts")
        expect(festive(2026, 3, 29).easter == 1 && !festive(2026, 3, 29).vacuumEars, "Palmsonntag: Osterstrauch")
        expect(festive(2026, 4, 4).easter == 1, "Karsamstag: Osterstrauch")
        f = festive(2026, 4, 5)
        expect(f.easter == 2 && f.vacuumEars && f.outfitTheme == .easter, "Ostersonntag: Eier, Hasenohren")
        expect(festive(2026, 4, 6).easter == 2, "Ostermontag: Eier")
        expect(festive(2026, 4, 7).easter == 0, "Dienstag nach Ostern: nichts")
        expect(festive(2026, 10, 23).halloween == 0, "23.10.: noch kein Halloween")
        f = festive(2026, 10, 24)
        expect(f.halloween == 1 && !f.vacuumGhost && f.outfitTheme == .none, "24.10.: Kürbis und Fledermäuse")
        f = festive(2026, 10, 31, 20)
        expect(f.halloween == 2 && f.vacuumGhost && f.outfitTheme == .halloween && f.outfitChance == 0.75, "31.10. abends: alles")
        expect(festive(2026, 10, 31, 10).outfitChance == 0.45, "31.10. morgens: weniger Kostüme")
        expect(festive(2026, 11, 1, 5).halloween == 2 && festive(2026, 11, 1, 7).halloween == 0, "Allerheiligen: bis 6 Uhr")
        f = festive(2026, 2, 14)
        expect(f.valentine && f.outfitTheme == .valentine, "Valentinstag")
        expect(!festive(2026, 2, 13).valentine, "13.2.: kein Valentinstag")

        print("Hook-Notfallparser")
        let cut = #"{"session_id":"abc","hook_event_name":"PreToolUse","tool_name":"Bash","description":"Build \"x\"\nTests","command":"swift bui"#
        let j = Hooks.looseFields(cut)
        expect(j["session_id"] as? String == "abc" && j["hook_event_name"] as? String == "PreToolUse" && j["tool_name"] as? String == "Bash", "Kopffelder")
        let input = j["tool_input"] as? [String: Any]
        expect(input?["description"] as? String == "Build \"x\" Tests", "Beschreibung mit Anführungszeichen und Zeilenumbruch")
        expect(input?["command"] == nil, "abgeschnittenes Feld fehlt statt halb")
        expect(Hooks.looseFields("kein json").isEmpty, "ohne Felder → leer")
        expect(Hooks.looseFields(#"{"session_id":"s","hook_event_name":"Stop"}"#)["tool_input"] == nil, "ohne Werkzeugfelder kein tool_input")

        print("Werkzeugtexte")
        expect(describeTool("Bash", ["description": "Baut die App", "command": "swift build"]) == "Baut die App", "Bash mit Beschreibung")
        expect(describeTool("Bash", ["command": "git status\ngit log"]) == "Terminal: git status", "Bash ohne Beschreibung: erste Zeile")
        expect(describeTool("Bash", [:]) == "Terminal", "Bash ohne alles")
        expect(describeTool("Edit", ["file_path": "/x/y/App.swift"]) == L("Bearbeitet App.swift", "Editing App.swift"), "Edit zeigt Dateinamen")
        expect(describeTool("NotebookEdit", ["notebook_path": "/x/a.ipynb"]) == L("Bearbeitet a.ipynb", "Editing a.ipynb"), "NotebookEdit")
        expect(describeTool("Agent", ["subagent_type": "Explore"]) == L("Delegiert an Explore", "Delegating to Explore"), "Agent mit Typ")
        expect(describeTool("Task", [:]) == L("Delegiert an Helfer", "Delegating to a helper"), "Task ohne Typ")
        expect(describeTool("mcp__homeassistant__ha_get_state", [:]) == L("Nutzt homeassistant", "Using homeassistant"), "MCP-Server")
        expect(describeTool("mcp__claude_ai_Claude_Docs__read", [:]) == L("Nutzt Claude_Docs", "Using Claude_Docs"), "MCP ohne claude_ai_-Präfix")
        expect(describeTool("Skill", ["skill": "run"]) == L("Lädt Skill", "Loading skill") + " run", "Skill")
        expect(describeTool("SomethingNew", [:]) == "SomethingNew", "unbekanntes Werkzeug: Name")

        print("Preise und Modellnamen")
        let mio = 1_000_000
        expect(Pricing.cost(model: "claude-opus-5-5", TokenTally(input: mio, cacheWrite: 0, cacheRead: 0, output: 0)) == 4, "Opus 5.5 Eingabe 4 $/Mio.")
        expect(Pricing.cost(model: "claude-opus-5-5", TokenTally(input: 0, cacheWrite: 0, cacheRead: 0, output: mio)) == 20, "Opus 5.5 Ausgabe 20 $/Mio.")
        expect(Pricing.cost(model: "claude-opus-5-5", TokenTally(input: 0, cacheWrite: mio, cacheRead: 0, output: 0)) == 5, "Cache schreiben 125 %")
        expect(Pricing.cost(model: "claude-opus-5-5", TokenTally(input: 0, cacheWrite: 0, cacheRead: mio, output: 0)).map { abs($0 - 0.4) < 1e-9 } == true, "Cache lesen 10 %")
        expect(Pricing.cost(model: "claude-sonnet-4-5-20250929", TokenTally(input: mio, cacheWrite: 0, cacheRead: 0, output: 0)) == 3, "Sonnet 4.5 Eingabe 3 $/Mio.")
        expect(Pricing.cost(model: "claude-fable-5-1", TokenTally(input: mio, cacheWrite: 0, cacheRead: 0, output: 0)) == 10, "Fable Eingabe 10 $/Mio.")
        expect(Pricing.cost(model: "gpt-5", TokenTally(input: mio, cacheWrite: 0, cacheRead: 0, output: 0)) == nil, "unbekanntes Modell → keine Kosten")
        expect(Pricing.cost(model: "claude-opus-4-1", TokenTally(input: mio, cacheWrite: 0, cacheRead: 0, output: 0)) == 15, "Opus 4.1 vor Opus 4 (Reihenfolge der Tabelle)")
        expect(shortModel("claude-opus-5-5") == "Opus 5.5", "Opus 5.5")
        expect(shortModel("claude-sonnet-4-5-20250929") == "Sonnet 4.5", "Datum fällt weg")
        expect(shortModel("claude-fable-5-1") == "Fable 5.1", "Fable 5.1")
        expect(shortModel("claude-haiku-4") == "Haiku 4", "einstellige Version")
        expect(shortModel("") == "" && shortModel("gpt-5") == "gpt-5", "leer bleibt leer, Fremdes bleibt wie es ist")

        print("Zeitstempel")
        let plain = parseISO8601("2026-10-17T10:00:00Z")
        expect(plain == Date(timeIntervalSince1970: 1_792_231_200), "ohne Bruchteile")
        let frac = parseISO8601("2026-10-17T10:00:00.250Z")
        expect(frac.map { abs($0.timeIntervalSince1970 - 1_792_231_200.25) < 0.001 } == true, "mit Bruchteilen")
        expect(parseISO8601("2026-10-17T12:00:00+02:00") == plain, "Zeitzonen-Offset")
        expect(parseISO8601("gestern") == nil && parseISO8601("") == nil, "Unsinn → nil")

        print("Sprache: \(Lang.isGerman ? "Deutsch" : "Englisch")")
        print(failures == 0 ? "\nAlle Tests bestanden." : "\n\(failures) Test(s) fehlgeschlagen.")
        exit(failures == 0 ? 0 : 1)
    }
}
