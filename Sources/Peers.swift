import Foundation
import Network
import CryptoKit
import IOKit.ps

// MARK: - Andere Macs im lokalen Netz
//
// Jede AgentBar meldet sich per Bonjour (_agentbar._tcp) an und schickt ihre eigenen Sitzungen an die anderen.
// Gekoppelt wird über einen gemeinsamen Code: daraus entstehen der Schlüssel (ChaChaPoly) und eine kurze
// Gruppenkennung im TXT-Eintrag, damit fremde AgentBars im selben WLAN gar nicht erst verbunden werden.
// Jede Nachricht ist verschlüsselt und authentifiziert – ohne den Code lässt sich nichts lesen oder einschleusen.

enum PeerCode {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // ohne I/O/0/1 – nichts zum Verwechseln
    static let length = 12

    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return format(String(bytes.map { alphabet[Int($0) % alphabet.count] }))
    }

    /// Eingabe säubern (Leerzeichen, Bindestriche, Kleinbuchstaben) – nil, wenn es kein gültiger Code ist.
    static func normalize(_ input: String) -> String? {
        let raw = input.uppercased().filter { $0.isLetter || $0.isNumber }
        guard raw.count == length, raw.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return format(raw)
    }

    private static func format(_ raw: String) -> String {
        stride(from: 0, to: raw.count, by: 4).map { i -> String in
            let a = raw.index(raw.startIndex, offsetBy: i)
            return String(raw[a..<raw.index(a, offsetBy: 4)])
        }.joined(separator: "-")
    }

    static func key(_ code: String, _ purpose: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(code.utf8)), salt: Data("agentbar-peers-v1".utf8),
                               info: Data(purpose.utf8), outputByteCount: 32)
    }

    static func group(_ code: String) -> String {
        key(code, "group").withUnsafeBytes { Data($0).prefix(6).map { String(format: "%02x", $0) }.joined() }
    }
}

/// Was über das Netz geht: nur Anzeige-Daten, keine Protokolle. Arbeitsordner im Home-Ordner relativ zu ~,
/// alle anderen nur mit ihrem letzten Pfadteil (Projektname).
private struct Envelope: Codable {
    var v = 1
    var from: String
    var name: String
    var laptop: Bool
    var sent: Double
    var sessions: [Wire]

    struct Wire: Codable {
        var id, cwd, model, mode, activity, tool, lastText, source: String
        var title: String?
        var status: Int
        var last: Double
        var ctx, window: Int
        var tokens: [String: [Int]]
        var helpers: [Helper]
        var q: String?            // Fragetext (ab 2.0; ältere Versionen ignorieren/fehlen → nil)
    }
    struct Helper: Codable {
        var id, type, description, activity: String
        var working: Bool
        var last: Double
    }
}

private extension AgentSession {
    var wire: Envelope.Wire {
        let home = NSHomeDirectory()
        let path = cwd == home || cwd.hasPrefix(home + "/") ? "~" + cwd.dropFirst(home.count) : URL(fileURLWithPath: cwd).lastPathComponent
        return .init(id: id, cwd: path, model: model, mode: permissionMode,
                     activity: activity, tool: tool, lastText: String(lastText.prefix(300)), source: source.rawValue, title: title,
                     status: status.rawValue, last: lastActivity.timeIntervalSince1970, ctx: contextUsed, window: contextWindow,
                     tokens: tokens.mapValues { [$0.input, $0.cacheWrite, $0.cacheRead, $0.output] },
                     helpers: subagents.prefix(12).map { .init(id: $0.id, type: $0.type, description: $0.description, activity: $0.activity,
                                                               working: $0.working, last: $0.lastActivity.timeIntervalSince1970) },
                     q: question.map { String($0.prefix(200)) })
    }

    init?(_ w: Envelope.Wire, device: String, laptop: Bool) {
        guard let status = AgentStatus(rawValue: w.status) else { return nil }
        let cwd = w.cwd.hasPrefix("~") ? NSHomeDirectory() + w.cwd.dropFirst() : w.cwd
        self.init(id: w.id, source: SessionSource(rawValue: w.source) ?? .cli, cwd: cwd, title: w.title, model: w.model,
                  permissionMode: w.mode, status: status, activity: w.activity, tool: w.tool, lastText: w.lastText,
                  lastActivity: Date(timeIntervalSince1970: w.last),
                  tokens: w.tokens.compactMapValues { $0.count == 4 ? TokenTally(input: $0[0], cacheWrite: $0[1], cacheRead: $0[2], output: $0[3]) : nil },
                  subagents: w.helpers.map { SubAgent(id: $0.id, type: $0.type, description: $0.description, working: $0.working,
                                                      activity: $0.activity, lastActivity: Date(timeIntervalSince1970: $0.last)) },
                  hostBundle: nil, tty: nil, usesHooks: false, contextUsed: w.ctx, contextWindow: w.window,
                  device: device, deviceIsLaptop: laptop, question: w.q.map { String($0.prefix(200)) })
    }
}

/// Ein anderer Mac, von dem gerade Daten kommen.
struct Peer: Identifiable, Equatable {
    let id: String
    var name: String
    var laptop: Bool
    var sessions: [AgentSession]
    var lastSeen: Date
    var lastSent: Double
}

@MainActor
final class PeerHub: ObservableObject {
    static let service = "_agentbar._tcp"
    @Published private(set) var peers: [String: Peer] = [:]
    @Published private(set) var problem: String?
    /// Neue Liste der Sitzungen anderer Macs (für den SessionMonitor).
    var onChange: (([AgentSession]) -> Void)?

    private let myID: String
    private var code: String?
    private var sealKey: SymmetricKey?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var links: [ObjectIdentifier: PeerLink] = [:]
    private var outgoing: [String: ObjectIdentifier] = [:]      // Peer-ID → Verbindung, die wir selbst aufgebaut haben
    private var lastResults: Set<NWBrowser.Result> = []
    private var local: [AgentSession] = []
    private var pending = false
    private var timer: Timer?
    private var group: String?
    private var restartDelay: TimeInterval = 2          // Backoff nach Ausfall von Listener/Browser (bis 60 s)
    private var restartPending = false
    static let maxLinks = 8
    private let name = Host.current().localizedName ?? "Mac"
    private let laptop = PeerHub.hasBattery()

    init(id: String? = nil) {
        let d = UserDefaults.standard
        if let id { myID = id } else if let id = d.string(forKey: "peerInstanceID") { myID = id } else {
            myID = UUID().uuidString.lowercased(); d.set(myID, forKey: "peerInstanceID")
        }
    }

    var enabled: Bool { listener != nil }

    /// Einstellungen übernehmen: an/aus, Code geändert.
    func configure() {
        let d = UserDefaults.standard
        let want = d.bool(forKey: Prefs.peersEnabled) ? d.string(forKey: Prefs.peerCode).flatMap(PeerCode.normalize) : nil
        guard want != code || (want != nil && listener == nil) else { return }
        stop()
        guard let want else { return }
        code = want
        sealKey = PeerCode.key(want, "seal")
        start(group: PeerCode.group(want))
    }

    /// Netzwechsel/Ruhezustand: Listener und Browser neu aufsetzen, Code bleibt.
    func restart() {
        guard let code, let key = sealKey else { return }
        stop()
        self.code = code
        sealKey = key
        start(group: PeerCode.group(code))
    }

    /// Nach einem Ausfall mit wachsender Pause neu starten.
    private func scheduleRestart() {
        guard !restartPending, code != nil else { return }
        restartPending = true
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 60)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            restartPending = false
            restart()
        }
    }

    /// Eigene Sitzungen haben sich geändert → gebündelt an alle schicken.
    func update(local sessions: [AgentSession]) {
        local = sessions.filter { $0.device == nil }
        guard enabled, !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pending = false
            self?.broadcast()
        }
    }

    // MARK: Start/Stopp

    private func start(group: String) {
        problem = nil
        self.group = group
        do {
            let l = try NWListener(using: .tcp)
            l.service = NWListener.Service(name: myID, type: Self.service, txtRecord: NWTXTRecord(["g": group, "i": myID]))
            l.newConnectionHandler = { [weak self] c in DispatchQueue.main.async { self?.adopt(c, peer: nil) } }
            l.stateUpdateHandler = { [weak self] st in
                DispatchQueue.main.async {
                    switch st {
                    case .failed(let e): self?.problem = e.localizedDescription; self?.scheduleRestart()
                    case .ready: self?.restartDelay = 2
                    default: break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            problem = error.localizedDescription
            scheduleRestart()
            return
        }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: Self.service, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async { self?.lastResults = results; self?.connectToPeers(group: group) }
        }
        b.stateUpdateHandler = { [weak self] st in
            DispatchQueue.main.async {
                switch st {
                case .failed(let e): self?.problem = e.localizedDescription; self?.scheduleRestart()
                case .waiting(let e): self?.problem = L("Lokales Netzwerk nicht erlaubt", "Local network not allowed") + " (\(e.localizedDescription))"
                case .ready: self?.problem = nil
                default: break
                }
            }
        }
        b.start(queue: .main)
        browser = b
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.housekeeping(group: group) }
        }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        group = nil
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        for l in links.values { l.cancel() }
        links = [:]; outgoing = [:]; lastResults = []
        code = nil; sealKey = nil
        if !peers.isEmpty { peers = [:]; publish() }
    }

    // MARK: Verbindungen

    /// Nur der Mac mit der kleineren ID baut die Verbindung auf – so gibt es je Paar genau eine.
    private func connectToPeers(group: String) {
        for r in lastResults {
            guard case .bonjour(let txt) = r.metadata, txt["g"] == group, let id = txt["i"], id != myID, myID < id,
                  outgoing[id] == nil else { continue }
            adopt(NWConnection(to: r.endpoint, using: .tcp), peer: id)
        }
    }

    private func adopt(_ c: NWConnection, peer: String?) {
        // Obergrenze gegen Fluten im lokalen Netz
        guard links.count < Self.maxLinks else { c.cancel(); return }
        let link = PeerLink(c)
        let key = ObjectIdentifier(link)
        links[key] = link
        if let peer { outgoing[peer] = key }
        link.onMessage = { [weak self] data in self?.received(data) ?? false }
        link.onReady = { [weak self, weak link] in if let link { self?.send(to: link) } }
        link.onClose = { [weak self] in
            guard let self else { return }
            self.links[key] = nil
            if let peer, self.outgoing[peer] == key { self.outgoing[peer] = nil }
        }
        link.start()
    }

    private func housekeeping(group: String) {
        // Weg ist, wer 35 s nichts geschickt hat; Verbindungen neu aufbauen, falls eine abgebrochen ist
        let cutoff = Date().addingTimeInterval(-35)
        let before = peers.count
        peers = peers.filter { $0.value.lastSeen > cutoff }
        if peers.count != before { publish() }
        connectToPeers(group: group)
        broadcast()
    }

    // MARK: Nachrichten

    private func broadcast() {
        for l in links.values where l.ready { send(to: l) }
    }

    private func send(to link: PeerLink) {
        guard let sealKey else { return }
        let env = Envelope(from: myID, name: name, laptop: laptop, sent: Date().timeIntervalSince1970, sessions: local.prefix(40).map(\.wire))
        guard let json = try? JSONEncoder().encode(env), let box = try? ChaChaPoly.seal(json, using: sealKey) else { return }
        link.send(box.combined)
    }

    /// false = nicht entschlüsselbar/lesbar → Verbindung wird geschlossen.
    private func received(_ data: Data) -> Bool {
        guard let sealKey, let box = try? ChaChaPoly.SealedBox(combined: data),
              let json = try? ChaChaPoly.open(box, using: sealKey),
              let env = try? JSONDecoder().decode(Envelope.self, from: json),
              env.v == 1, env.from != myID else { return false }
        // Nur frische Nachrichten, und nie ältere nach neueren (gegen Wiedereinspielen)
        let now = Date().timeIntervalSince1970
        guard abs(now - env.sent) < 120, env.sent > (peers[env.from]?.lastSent ?? 0) else { return true }
        let name = String(env.name.prefix(40))
        let list = env.sessions.prefix(40).compactMap { AgentSession($0, device: name, laptop: env.laptop) }
        let changed = peers[env.from]?.sessions != list || peers[env.from]?.name != name
        peers[env.from] = Peer(id: env.from, name: name, laptop: env.laptop, sessions: list, lastSeen: Date(), lastSent: env.sent)
        if changed { publish() }
        return true
    }

    private func publish() {
        onChange?(peers.values.sorted { $0.name < $1.name }.flatMap(\.sessions))
    }

    private static func hasBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { src in
            let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any]
            return d?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }
}

/// Eine TCP-Verbindung mit Längen-Präfix (4 Byte) je Nachricht.
@MainActor
private final class PeerLink {
    private let c: NWConnection
    private(set) var ready = false
    private var trusted = false               // erste gültige Nachricht empfangen
    var onMessage: ((Data) -> Bool)?
    var onReady: (() -> Void)?
    var onClose: (() -> Void)?
    private static let maxFrame = 512_000      // 40 Sitzungen passen locker hinein
    private static let handshakeTimeout: TimeInterval = 10

    init(_ c: NWConnection) { self.c = c }

    func start() {
        // Wer nach 10 s nichts Gültiges geschickt hat, fliegt raus
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handshakeTimeout) { [weak self] in
            guard let self, !self.trusted else { return }
            self.close()
        }
        c.stateUpdateHandler = { [weak self] st in
            DispatchQueue.main.async {
                guard let self else { return }
                switch st {
                case .ready: self.ready = true; self.onReady?(); self.readLength()
                case .failed, .cancelled: self.close()
                case .waiting: self.c.cancel()
                default: break
                }
            }
        }
        c.start(queue: .main)
    }

    func cancel() { c.cancel() }

    private func close() {
        guard onClose != nil else { return }
        ready = false
        c.cancel()
        let done = onClose
        onClose = nil
        done?()
    }

    func send(_ data: Data) {
        var len = UInt32(data.count).bigEndian
        var frame = Data(bytes: &len, count: 4)
        frame.append(data)
        c.send(content: frame, completion: .contentProcessed { [weak self] e in
            if e != nil { DispatchQueue.main.async { self?.close() } }
        })
    }

    private func readLength() {
        c.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, done, err in
            DispatchQueue.main.async {
                guard let self else { return }
                guard err == nil, !done, let data, data.count == 4 else { self.close(); return }
                let n = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
                guard n > 0, n <= Self.maxFrame else { self.close(); return }
                self.readBody(n)
            }
        }
    }

    private func readBody(_ n: Int) {
        c.receive(minimumIncompleteLength: n, maximumLength: n) { [weak self] data, _, done, err in
            DispatchQueue.main.async {
                guard let self else { return }
                guard err == nil, let data, data.count == n else { self.close(); return }
                // Nicht entschlüsselbar → sofort schließen
                guard self.onMessage?(data) == true else { self.close(); return }
                self.trusted = true
                if done { self.close() } else { self.readLength() }
            }
        }
    }
}
