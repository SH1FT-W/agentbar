// Sync test, not in CI (needs Bonjour on the local network): three PeerHubs in one process, plus a flooder that
// keeps idle TCP connections open to every listener. Build: `./build.sh peertest`
import Foundation
import Network

@main
struct PeerTest {
    @MainActor static func main() {
        let code = PeerCode.generate()
        UserDefaults.standard.set(true, forKey: Prefs.peersEnabled)
        UserDefaults.standard.set(code, forKey: Prefs.peerCode)
        let hubs = (0..<3).map { PeerHub(id: "test-\($0)-\(UUID().uuidString.prefix(6))") }
        var got = [[AgentSession]](repeating: [], count: 3)
        for (i, h) in hubs.enumerated() { h.onChange = { got[i] = $0 } }
        func s(_ id: String) -> AgentSession {
            AgentSession(id: id, source: .cli, cwd: "/x", title: id, model: "m", permissionMode: "", status: .working, activity: "",
                         tool: "", lastText: "", lastActivity: Date(), tokens: [:], subagents: [], hostBundle: "com.apple.Terminal",
                         tty: nil, usesHooks: true)
        }
        hubs.forEach { $0.configure() }
        var flood: [NWConnection] = []
        func wait(_ what: String, _ secs: Double, _ ok: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(secs)
            while Date() < end { if ok() { print("  ✓ \(what) (\(String(format: "%.1f", secs - end.timeIntervalSinceNow)) s)"); return true }
                RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
            print("  ✗ \(what)"); return false
        }
        var ok = true
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        for (i, h) in hubs.enumerated() { h.update(local: [s("s\(i)")]) }
        ok = wait("alle drei sehen die zwei anderen", 20) { got.allSatisfy { $0.count == 2 } } && ok
        // Flooder: keep idle TCP connections open to every listener port of this process
        let ports = listeningPorts()
        print("  Listener-Ports: \(ports)")
        func refill() {
            flood.removeAll { if case .cancelled = $0.state { return true }; if case .failed = $0.state { return true }; return false }
            for p in listeningPorts() { for _ in 0..<4 { let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: p)!, using: .tcp); c.start(queue: .main); flood.append(c) } }
        }
        let floodTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in MainActor.assumeIsolated { refill() } }
        refill()
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        // Wake/network change: all links are rebuilt while the flood goes on
        hubs.forEach { $0.restart() }
        for (i, h) in hubs.enumerated() { h.update(local: [s("s\(i)"), s("n\(i)")]) }
        ok = wait("nach Neustart trotz offener Fremdverbindungen wieder verbunden", 40) { got.allSatisfy { $0.count == 4 } } && ok
        floodTimer.invalidate()
        flood.forEach { $0.cancel() }
        print(ok ? "OK" : "FEHLER")
        exit(ok ? 0 : 1)
    }

    static func listeningPorts() -> [UInt16] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-nP", "-a", "-p", "\(getpid())", "-iTCP", "-sTCP:LISTEN", "-Fn"]
        let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Array(Set(out.split(separator: "\n").filter { $0.hasPrefix("n") }.compactMap { UInt16($0.split(separator: ":").last ?? "") }))
    }
}
