import SwiftUI
import ZenCore
import ZenUI
#if os(macOS)
import AppKit
import Darwin
#endif

@main struct ZenApp: App {
    @StateObject private var model: ZenModel
    init() {
        #if os(macOS)
        InstanceGuard.acquire()
        #endif
        _model = StateObject(wrappedValue: ZenModel())
    }
    #if os(macOS)
    @NSApplicationDelegateAdaptor(ZenDelegate.self) private var delegate
    #endif
    var body: some Scene {
        #if os(macOS)
        Window("禅", id: "zen") {
            ZenRootView(model: model).frame(minWidth: 430, idealWidth: 480, minHeight: 560, idealHeight: 720)
        }.defaultSize(width: 480, height: 720).windowStyle(.hiddenTitleBar)
        MenuBarExtra {
            ZenMenuView(model: model)
        } label: {
            if model.active != nil { Text("禅 \(durationText(model.remaining))").monospacedDigit() }
            else { Text(model.pendingCount > 0 ? "禅 ·" : "禅") }
        }.menuBarExtraStyle(.window)
        #else
        WindowGroup { ZenRootView(model: model) }
        #endif
    }
}

#if os(macOS)
enum InstanceGuard {
    static var lockFD: Int32 = -1
    static func acquire() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zen")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { NSLog("Zen lock: %@", error.localizedDescription); exit(1) }
        lockFD = open(dir.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if let bundle = Bundle.main.bundleIdentifier {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?.activate(options: [])
            }
            exit(0)
        }
    }
}
final class ZenDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#endif
