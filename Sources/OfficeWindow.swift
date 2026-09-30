import SwiftUI
import Darwin

/// Eigenes Fenster fürs Büro: randlos wirkend (durchsichtige Titelleiste), festes Seitenverhältnis, merkt sich Position.
@MainActor
final class OfficeWindowController: NSObject, NSWindowDelegate {
    private weak var store: AppStore?
    private var window: NSWindow?
    let model = OfficeModel()
    let load = SystemLoad()

    init(store: AppStore) { self.store = store }

    var isOpen: Bool { window?.isVisible == true }

    func toggle() { isOpen ? close() : show() }

    func show() {
        guard let store else { return }
        if window == nil {
            let root = OfficeView(model: model, load: load)
                .environmentObject(store.monitor)
                .environmentObject(store.quota)
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
    }

    func close() {
        window?.orderOut(nil)
        load.stop()
        UserDefaults.standard.set(false, forKey: "officeWasOpen")
    }

    func applyPrefs() {
        let d = UserDefaults.standard
        window?.level = d.bool(forKey: Prefs.officeFloating) ? .floating : .normal
        window?.alphaValue = CGFloat(max(0.4, d.double(forKey: Prefs.officeOpacity)))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { close(); return false }
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
