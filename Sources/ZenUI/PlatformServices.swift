import Foundation
import UserNotifications
import ZenCore
#if os(macOS)
import AppKit
import Carbon
import ServiceManagement
#else
import UIKit
#endif

@MainActor final class CompletionNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((UUID) -> Void)?
    var onStatus: ((String) -> Void)?
    private var pendingIDs: Set<UUID> = []
    func configure() { UNUserNotificationCenter.current().delegate = self }
    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func schedule(session: ActiveSession, sound: Bool) {
        pendingIDs.insert(session.id)
        Task {
            do {
                let granted = try await requestPermission()
                guard granted else { onStatus?("系统通知未允许，到时会保留待补记记录。"); pendingIDs.remove(session.id); return }
                guard pendingIDs.contains(session.id), session.remaining(at: ContinuousTime.now) > 0 else { return }
                let content = UNMutableNotificationContent()
                content.title = session.isRest ? "歇息结束" : "这一刻，已走过"
                content.body = session.isRest ? "准备好了，再开始下一段专注。" : "刚才这段时间，你做了什么？"
                // Mac rings directly from its running timer. iOS uses this sound while suspended.
                #if os(iOS)
                if sound {
                    let file = try SoundPlayer.installBellNotificationSound(volume: session.soundVolume ?? 0.65)
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: file.lastPathComponent))
                }
                #endif
                let request = UNNotificationRequest(identifier: session.id.uuidString, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(max(1, session.remaining(at: ContinuousTime.now))), repeats: false))
                try await UNUserNotificationCenter.current().add(request)
                if !pendingIDs.contains(session.id) { cancel(session.id) }
            } catch { onStatus?("系统提醒未设置：\(error.localizedDescription)") }
        }
    }
    func cancel(_ id: UUID) {
        pendingIDs.remove(id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
    func complete(session: ActiveSession, recent: Bool, play: @escaping () -> Void) {
        #if os(macOS)
        // Authorization is not evidence that a system alert was audible. Always ring in-app on Mac.
        cancel(session.id)
        if session.completionSound != false { play() }
        #else
        if UIApplication.shared.applicationState != .background {
            cancel(session.id)
            // Reopening long after a background alert should show the entry, not ring twice.
            if recent && session.completionSound != false { play() }
        } else if session.completionSound != false {
            if session.notificationEnabled == false { play(); return }
            Task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional || settings.soundSetting != .enabled {
                    play()
                }
            }
        }
        #endif
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner]) // Foreground audio is delivered by the app, exactly once.
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = UUID(uuidString: response.notification.request.identifier)
        Task { @MainActor in if let id { self.onOpen?(id) } }; completionHandler()
    }
}

#if os(macOS)
@MainActor final class GlobalShortcuts {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onStart: (() -> Void)?
    var onAbandon: (() -> Void)?
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let shortcuts = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            let keyID = id.id
            Task { @MainActor in if keyID == 1 { shortcuts.onStart?() } else { shortcuts.onAbandon?() } }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
    func register(_ settings: Preferences) throws {
        guard handler != nil else { throw RecordError.unavailable("全局快捷键事件处理器未能安装") }
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll()
        guard settings.startKey != settings.abandonKey || settings.startModifiers != settings.abandonModifiers else {
            throw RecordError.unavailable("开始和放弃不能使用相同快捷键")
        }
        for (index, key, modifiers) in [(UInt32(1), settings.startKey, settings.startModifiers), (UInt32(2), settings.abandonKey, settings.abandonModifiers)] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x5A454E31, id: index), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll()
                throw RecordError.unavailable("快捷键被其他应用占用，请更换组合")
            }
            refs.append(ref)
        }
    }
}
#endif
