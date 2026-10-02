import SwiftUI
import Darwin

/// Eigenes Fenster fürs Büro: randlos wirkend (durchsichtige Titelleiste), festes Seitenverhältnis, merkt sich Position.
@MainActor
final class OfficeWindowController: NSObject, NSWindowDelegate {
    private weak var store: AppStore?
    private var window: NSWindow?
    let model = OfficeModel()
    let load = SystemLoad()
    let visibility = OfficeVisibility()

    init(store: AppStore) { self.store = store }

    var isOpen: Bool { window?.isVisible == true }

    func toggle() { isOpen ? close() : show() }

    func show() {
        guard let store else { return }
        if window == nil {
            let root = OfficeView(model: model, load: load, visibility: visibility)
                .environmentObject(store.monitor)
                .environmentObject(store.quota)
                .environmentObject(store.stats)
            let host = NSHostingView(rootView: root)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = L("Büro", "Office")
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.contentAspectRatio = NSSize(width: OfficeScene.size.width, height: OfficeScene.size.height)
            w.minSize = NSSize(width: 480, height: 288)
            w.contentView = host
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if !w.setFrameUsingName("AgentBarOffice") { w.center() }
            w.setFrameAutosaveName("AgentBarOffice")
            window = w
        }
        applyPrefs()
        load.start()
        window?.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: "officeWasOpen")
        store.objectWillChange.send()   // Menüeintrag „Büro öffnen/schließen“ sofort umstellen
    }

    func close() {
        window?.orderOut(nil)
        load.stop()
        UserDefaults.standard.set(false, forKey: "officeWasOpen")
        store?.objectWillChange.send()
    }

    func applyPrefs() {
        let d = UserDefaults.standard
        window?.level = d.bool(forKey: Prefs.officeFloating) ? .floating : .normal
        window?.alphaValue = CGFloat(max(0.4, d.double(forKey: Prefs.officeOpacity)))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { close(); return false }
    // Im Dock abgelegt/zurückgeholt zählt auch als zu/offen
    func windowDidMiniaturize(_ notification: Notification) { store?.objectWillChange.send() }
    func windowDidDeminiaturize(_ notification: Notification) { store?.objectWillChange.send() }

    /// Verdeckt, im Dock oder auf einem anderen Space: Animation und CPU-Messung pausieren.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let w = window else { return }
        let visible = w.isVisible && w.occlusionState.contains(.visible)
        if visibility.visible != visible { visibility.visible = visible }
        if visible { load.start() } else { load.stop() }
    }
}

/// Ob das Bürofenster gerade überhaupt zu sehen ist (NSWindow.occlusionState).
final class OfficeVisibility: ObservableObject {
    @Published var visible = true
}

/// CPU-Last für den Saugroboter (je mehr Last, desto flotter fährt er).
final class SystemLoad: ObservableObject {
    private(set) var cpu: Double = 0.1
    private var timer: Timer?
    private var last: (used: UInt64, total: UInt64)?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        sample()
    }
    func stop() { timer?.invalidate(); timer = nil }

    /// Stand des Saugroboters – aufsummiert, damit ein Lastwechsel nur das Tempo ändert, statt ihn springen zu lassen.
    /// Brennt das Licht (dock), biegt er beim nächsten Vorbeikommen in die Ladestation ab; wird es hell, fährt er wieder los.
    private var odometer: (t: Double, v: VacuumState)?
    func vacuum(at now: Double, dock: Bool) -> VacuumState {
        guard let o = odometer else {
            let v = dock ? VacuumState.docked : VacuumState(loop: 0, spur: 0)   // nachts gestartet: steht schon in der Station
            odometer = (now, v)
            return v
        }
        var v = o.v
        var step = min(max(now - o.t, 0), 0.5) * (20 + cpu * 140)
        let spurLen = OfficeScene.vacuumSpurLength, loopLen = OfficeScene.vacuumLoopLength
        if dock {
            if v.spur == 0 {
                var ahead = OfficeScene.vacuumJunctionDistance - v.loop.truncatingRemainder(dividingBy: loopLen)
                if ahead < 0 { ahead += loopLen }
                if ahead > loopLen - 1 { ahead = 0 }            // Rundungsrest: steht schon am Abzweig
                let m = min(step, ahead)
                v.loop += m
                step -= m
            }
            v.spur = min(spurLen, v.spur + step)
        } else {
            let back = min(v.spur, step)
            v.spur -= back
            v.loop += step - back
        }
        odometer = (now, v)
        return v
    }

    private func sample() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let used = user + sys + nice, total = used + idle
        if let l = last, total > l.total { cpu = Double(used - l.used) / Double(total - l.total) }
        last = (used, total)
    }
}
