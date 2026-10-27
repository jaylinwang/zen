import Foundation
import SwiftUI
import AppKit
import AVFoundation
import Carbon
import ZenCore
@testable import ZenUI

struct Failure: Error, CustomStringConvertible { var description: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String, line: UInt = #line) throws {
    guard try condition() else { throw Failure(description: "Line \(line): \(message)") }
}

@main struct ZenChecks {
    @MainActor static func main() throws {
        if CommandLine.arguments.contains("--verify-navigation") {
            _ = NSApplication.shared
            let support = FileManager.default.temporaryDirectory.appendingPathComponent("ZenNavigation-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: support) }
            let data = support.appendingPathComponent("records-root")
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            let model = ZenModel(supportDirectory: support, servicesEnabled: false)
            let host = NSHostingView(rootView: ZenRootView(model: model).frame(width: 480, height: 820))
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host; window.orderFront(nil)
            func settle(_ seconds: Double = 0.1) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
            settle(0.3)
            model.openWindow = {} // Isolate this fixture from the user's application windows.
            func click(_ x: CGFloat, _ y: CGFloat) {
                for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: kind, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0)!
                    window.sendEvent(event)
                }
                settle()
            }
            // Hit padding above/below and to the left of each label, not just the glyphs.
            for (index, x) in [(0, CGFloat(300)), (1, CGFloat(356)), (2, CGFloat(412))] {
                for y: CGFloat in [768, 796] {
                    model.selectedTab = (index + 1) % 3; settle()
                    click(x, y)
                    try expect(model.selectedTab == index, "Navigation padding must be clickable: tab \(index), point \(x),\(y)")
                }
            }
            model.chooseDirectory(data); model.start(continuousNow: 100)
            let id = model.active!.id; model.tick(at: 1600); settle(0.5)
            try expect(window.attachedSheet != nil, "Completion shows its annotation sheet")
            model.editorID = nil; settle(0.5)
            try expect(window.attachedSheet == nil, "Closing annotation removes the modal sheet")
            click(412, 768); try expect(model.selectedTab == 2, "Navigation works after closing annotation")
            model.showRecord(id); settle(0.5)
            model.saveAnnotation(id, skip: true); settle(0.5)
            try expect(window.attachedSheet == nil, "Saving annotation removes the modal sheet")
            click(300, 796); try expect(model.selectedTab == 0, "Navigation works after saving annotation")
            window.orderOut(nil)
            print("PASS Native mouse clicks cover all three navigation buttons, including after annotation close and save")
            return
        }
        if CommandLine.arguments.contains("--verify-bundled-audio") {
            let resources = Bundle.main.resourceURL!.appendingPathComponent("Zen_ZenUI.bundle/mokugyo.wav")
            try expect(FileManager.default.fileExists(atPath: resources.path), "Portable application includes its own recording")
            let player = try AVAudioPlayer(data: SoundPlayer.wave(choice: .wood, interval: 2), fileTypeHint: "wav")
            try expect(abs(player.duration - 2) < 0.01, "Packaged audio is playable")
            print("PASS Standalone application resolves bundled recorded audio (2-second interval)")
            return
        }
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--crash-worker" {
            let support = URL(fileURLWithPath: CommandLine.arguments[2])
            let data = URL(fileURLWithPath: CommandLine.arguments[3])
            let model = ZenModel(supportDirectory: support, servicesEnabled: false)
            model.chooseDirectory(data)
            let start = ContinuousTime.now
            model.start(continuousNow: start); model.tick(at: start + 5)
            guard let session = model.active, try Journal(directory: support).load().active?.id == session.id else { exit(2) }
            kill(getpid(), SIGKILL)
            exit(3)
        }
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("ZenChecks-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        func directories(_ name: String) throws -> (URL, URL) {
            let support = sandbox.appendingPathComponent(name + "/support")
            let records = sandbox.appendingPathComponent(name + "/data")
            try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
            return (support, records)
        }
        var passed = 0
        func check(_ title: String, _ run: () throws -> Void) throws {
            try run(); passed += 1; print("PASS \(title)")
        }
        try check("Blank start, target snapshot, checkpoint, completion, annotation") {
            let (support, data) = try directories("flow")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false)
            model.start(continuousNow: 100); try expect(model.active == nil, "No silent fallback directory")
            model.chooseDirectory(data); try expect(model.directory != nil, model.errorMessage ?? "Directory")
            model.start(continuousNow: 100); let id = model.active!.id
            model.preferences.focusMinutes = 45; model.savePreferences()
            try expect(model.active!.targetSeconds == 1500, "Settings affect next session")
            model.tick(at: 105)
            try expect(try Journal(directory: support).load().active!.checkpointSeconds == 5, "Checkpoint persisted")
            model.tick(at: 1600)
            try expect(model.active == nil, "Completion ends session")
            try expect(model.records.first!.record.focusedSeconds == 1500, "Full session duration")
            try expect(model.records.first!.record.outcome == .completed, "Completed outcome")
            try expect(model.drafts.count == 1, "Pending annotation")
            var draft = model.drafts[0]; draft.record.content = "读了几页书\n注意力回来了"; model.updateDraft(draft)
            model.saveAnnotation(id)
            try expect(model.drafts.isEmpty, model.errorMessage ?? "Draft cleared after durable save")
            try expect(model.records.first!.record.content == draft.record.content, "Content saved")
            try expect(model.records.first!.id == id, "Stable identity")
        }
        try check("Abandon leaves no record, pending annotation or counted time after relaunch") {
            let (support, data) = try directories("discard")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.start(continuousNow: 100); model.tick(at: 105); model.abandon(at: 580)
            try expect(model.active == nil && model.remaining == 0, "Timer ends immediately")
            try expect(model.records.isEmpty && model.drafts.isEmpty && model.pendingCount == 0 && model.todaySeconds == 0, "Abandoned time leaves no trace")
            try expect(try RecordStore(root: data).scan().records.isEmpty, "No Markdown created")
            let state = try Journal(directory: support).load()
            try expect(state.active == nil && state.drafts.isEmpty, "Running recovery cleared")
            let restored = ZenModel(supportDirectory: support, servicesEnabled: false)
            try expect(restored.active == nil && restored.drafts.isEmpty && restored.records.isEmpty, "Discarded session does not return on relaunch")
            model.start(continuousNow: 1000); model.tick(at: 2500)
            let completedID = model.drafts[0].id
            model.start(continuousNow: 3000); model.abandon(at: 3010)
            try expect(model.drafts.count == 1 && model.drafts[0].id == completedID && model.todaySeconds == 1500, "Abandon leaves earlier completed drafts intact")
        }
        try check("Late tick caps duration, multiple pending records survive relaunch") {
            let (support, data) = try directories("pending")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.start(label: "阅读", continuousNow: 100); model.tick(at: 9000)
            model.start(continuousNow: 10000); model.tick(at: 20000)
            try expect(model.records.count == 2 && model.drafts.count == 2, "New focus does not depend on annotation")
            try expect(model.records.allSatisfy { $0.record.focusedSeconds == 1500 }, "No overtime")
            let restored = ZenModel(supportDirectory: support, servicesEnabled: false)
            try expect(restored.drafts.count == 2 && restored.active == nil, "Relaunch pending recovery")
            let draft = restored.drafts.first { $0.record.content == "阅读" }!
            try expect(draft.record.labelOrigin == .before_session, "Preselected name preserved")
        }
        try check("Mac crash recovery retains checkpoint without resuming") {
            let (support, data) = try directories("crash")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.start(continuousNow: 100); let id = model.active!.id; model.tick(at: 110)
            let restored = ZenModel(supportDirectory: support, servicesEnabled: false)
            try expect(restored.active == nil, "No resume after crash on Mac")
            let draft = restored.drafts.first!
            try expect(draft.record.id == id && draft.record.focusedSeconds == 10 && draft.record.outcome == .interrupted, "Interrupted checkpoint retained")
            try expect(restored.retryDraft(id), restored.errorMessage ?? "Retry interrupted record")
            try expect(restored.records.count == 1, "No duplicate")
        }
        try check("Directory failure preserves draft; retry writes once") {
            let (support, data) = try directories("failure")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.start(continuousNow: 100)
            try FileManager.default.removeItem(at: data)
            model.tick(at: 10000)
            try expect(model.drafts.count == 1 && model.errorMessage != nil, "Failure surfaced with retained data")
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            let id = model.drafts[0].id
            try expect(model.retryDraft(id), model.errorMessage ?? "Retry failed")
            try expect(try RecordStore(root: data).scan().records.count == 1, "Exactly one persisted record")
        }
        try check("Draft edit baseline survives restart and protects external edit") {
            let (support, data) = try directories("conflict")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.start(continuousNow: 100); model.tick(at: 10000)
            let snapshot = model.records[0]; var draft = model.drafts[0]; draft.record.content = "尚未提交"; model.updateDraft(draft)
            let external = snapshot.record.annotated(content: "另一端已写", notes: "", reference: "")
            try MarkdownCodec.encode(external).write(to: snapshot.url, atomically: true, encoding: .utf8)
            let restored = ZenModel(supportDirectory: support, servicesEnabled: false)
            restored.saveAnnotation(draft.id)
            try expect(restored.drafts.count == 1 && restored.errorMessage != nil, "Conflict preserves draft")
            try expect(try RecordStore(root: data).scan().records[0].record.content == "另一端已写", "External file intact")
        }
        try check("Rest does not produce focus records or automatically start focus") {
            let (support, data) = try directories("rest")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.start(rest: true, continuousNow: 100); model.tick(at: 500)
            try expect(model.active == nil && model.records.isEmpty && model.drafts.isEmpty, "Rest is separate")
        }
        try check("Malformed recovery is retained and blocks new sessions") {
            let (support, data) = try directories("corrupt")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let path = support.appendingPathComponent("recovery.json"); try "broken".write(to: path, atomically: true, encoding: .utf8)
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data); model.start()
            try expect(!model.recoveryHealthy && model.active == nil, "No destructive recovery")
            try expect(try String(contentsOf: path) == "broken", "Original recovery kept")
        }
        try check("Abandon remains terminal when local journal is unwritable") {
            let (support, data) = try directories("journal-failure")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.start(continuousNow: 100)
            let backup = support.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: support, to: backup)
            try Data("temporarily unavailable".utf8).write(to: support)
            model.abandon(at: 580)
            try expect(model.active == nil, "Abandon must never restart the timer after a write failure")
            try expect(model.drafts.isEmpty && model.records.isEmpty, "Abandoned session never becomes a record")
            try expect(!model.canStart, "Avoid starting another session while recovery storage is unavailable")
            try FileManager.default.removeItem(at: support)
            try FileManager.default.moveItem(at: backup, to: support)
            model.retryRecovery()
            try expect(model.canStart, "Start re-enabled only after recovery is durable")
            let restored = ZenModel(supportDirectory: support, servicesEnabled: false)
            try expect(restored.active == nil && restored.drafts.isEmpty && restored.records.isEmpty, "Retried discard survives relaunch without a record")
        }
        try check("Legacy abandoned records remain readable, excluded from totals and explicitly deletable") {
            let (support, data) = try directories("delete-failure")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            let legacy = ActiveSession(targetSeconds: 1500).finished(outcome: .abandoned, elapsed: 480)
            let saved = try RecordStore(root: data).save(legacy)
            model.refresh(); model.beginEditing(saved)
            try expect(model.records.count == 1 && model.todaySeconds == 0, "Existing files preserved without counting abandoned time")
            let backup = support.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: support, to: backup)
            try Data("temporarily unavailable".utf8).write(to: support)
            model.deleteRecord(saved.id)
            try expect(FileManager.default.fileExists(atPath: saved.url.path), "Deletion must wait for journal update")
            try expect(model.drafts.count == 1, "Draft remains after failed deletion")
            try FileManager.default.removeItem(at: support); try FileManager.default.moveItem(at: backup, to: support)
            model.retryRecovery(); model.deleteRecord(saved.id)
            try expect(model.records.isEmpty && model.drafts.isEmpty, "Successful retry removes both")
            let restored = ZenModel(supportDirectory: support, servicesEnabled: false)
            try expect(restored.drafts.isEmpty && restored.records.isEmpty, "Deleted record must not reappear on relaunch")
        }
        try check("Completed and interrupted records can be deleted without reviving drafts") {
            for outcome in [Outcome.completed, .interrupted] {
                let (support, data) = try directories("delete-" + outcome.rawValue)
                let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
                let record = ActiveSession(targetSeconds: 60).finished(outcome: outcome, elapsed: 60)
                let saved = try RecordStore(root: data).save(record)
                model.refresh(); model.beginEditing(saved)
                model.deleteRecord(saved.id)
                try expect(model.records.isEmpty && model.drafts.isEmpty && model.editorID == nil, "Delete clears file, draft and editor")
                try expect(model.todaySeconds == 0 && model.pendingCount == 0, "Deleted time and pending count disappear")
                let restored = ZenModel(supportDirectory: support, servicesEnabled: false)
                try expect(restored.records.isEmpty && restored.drafts.isEmpty, "Deleted record stays deleted after relaunch")
            }
        }
        try check("Interrupted draft without a file is deletable; changed files remain protected") {
            let (support, data) = try directories("delete-draft")
            let record = ActiveSession(targetSeconds: 60).finished(outcome: .interrupted, elapsed: 20)
            var state = RecoveryState()
            state.drafts = [EditDraft(record: record, directoryPath: data.path)]
            try Journal(directory: support).save(state)
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.deleteRecord(record.id)
            try expect(try Journal(directory: support).load().drafts.isEmpty, "Unsaved interrupted draft is removed durably")
            let saved = try RecordStore(root: data).save(record)
            model.refresh(); model.beginEditing(saved)
            var changed = record; changed.content = "Edited outside the app"
            let external = try RecordStore(root: data).save(changed, expected: saved)
            model.deleteRecord(record.id)
            try expect(try String(contentsOf: saved.url) == external.source, "Concurrent external edit must survive")
            try expect(model.drafts.count == 1 && model.errorMessage != nil, "Failed delete restores draft and reports conflict")
        }
        try check("Persisted out-of-range settings are normalized before starting") {
            let (support, data) = try directories("settings-range")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            var p = Preferences(); p.focusMinutes = Int.max; p.restMinutes = -100; p.volume = 5; p.woodInterval = -20
            try JSONEncoder().encode(p).write(to: support.appendingPathComponent("preferences.json"))
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.start(continuousNow: 100)
            try expect(model.active?.targetSeconds == 240 * 60, "Bounded duration without overflow")
            try expect(model.preferences.restMinutes == 1 && model.preferences.volume == 1 && model.preferences.woodInterval == 1, "Safe control values")
        }
        try check("Old default cadence migrates once while later custom choices persist") {
            let (support, _) = try directories("cadence-migration")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as! [String: Any]
            old.removeValue(forKey: "soundDefaultsVersion"); old["woodInterval"] = 3; old["volume"] = 0.6
            try JSONSerialization.data(withJSONObject: old).write(to: support.appendingPathComponent("preferences.json"))
            let model = ZenModel(supportDirectory: support, servicesEnabled: false)
            try expect(model.preferences.woodInterval == 2 && model.preferences.volume == 0.6, "New default cadence preserves other preferences")
            model.preferences.woodInterval = 3; model.savePreferences()
            let restored = ZenModel(supportDirectory: support, servicesEnabled: false)
            try expect(restored.preferences.woodInterval == 3, "User can still choose three seconds after migration")
        }
        try check("Native marked-text Return commits without submitting; Shift-Return inserts newline") {
            _ = NSApplication.shared
            let editor = ComposingTextView.Editor(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
            let window = NSWindow(contentRect: editor.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = editor; window.makeFirstResponder(editor)
            var submissions = 0; editor.submit = { submissions += 1 }
            @MainActor func key(_ flags: NSEvent.ModifierFlags = []) -> NSEvent {
                NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                 windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            }
            editor.setMarkedText("你好", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            try expect(editor.hasMarkedText(), "Native composition active")
            editor.keyDown(with: key())
            try expect(submissions == 0, "Candidate confirmation must not submit")
            editor.unmarkText()
            editor.keyDown(with: key())
            try expect(submissions == 1, "Unmarked Enter submits")
            let previousLength = editor.string.count
            editor.keyDown(with: key(.shift))
            try expect(submissions == 1 && editor.string.count > previousLength && editor.string.contains("\n"), "Shift-Enter preserves multiline entry")
        }
        try check("Real wood retains its character with a soft tail, safe peaks and exact loop spacing") {
            let wood = try AVAudioPlayer(data: SoundPlayer.wave(choice: .wood, interval: Preferences().woodInterval), fileTypeHint: "wav")
            let slow = try AVAudioPlayer(data: SoundPlayer.wave(choice: .wood, interval: 7), fileTypeHint: "wav")
            let rain = try AVAudioPlayer(data: SoundPlayer.wave(choice: .rain, interval: 3), fileTypeHint: "wav")
            let source = try SoundPlayer.woodRecording()
            let loop = try SoundPlayer.wave(choice: .wood, interval: Preferences().woodInterval)
            try expect(source.count > 1000 && source.count < 44100, "Compact recorded strike with natural tail")
            func pcm(_ wave: Data) -> [Double] {
                stride(from: 44, to: wave.count, by: 2).map { offset in
                    Double(Int16(bitPattern: UInt16(wave[offset]) | (UInt16(wave[offset + 1]) << 8)))
                }
            }
            let samples = pcm(loop)
            let dot = zip(source, samples).reduce(0.0) { $0 + Double($1.0) * $1.1 }
            let dryEnergy = source.reduce(0.0) { $0 + Double($1) * Double($1) }
            let processedEnergy = samples.prefix(source.count).reduce(0.0) { $0 + $1 * $1 }
            try expect(dot / sqrt(dryEnergy * processedEnergy) > 0.7, "The original recorded strike still dominates")
            let tailEnergy = samples[30870..<57330].reduce(0.0) { $0 + $1 * $1 }
            try expect(tailEnergy / Double(57330 - 30870) > 144, "Audible room decay extends beyond the original recording")
            try expect(samples.suffix(8820).allSatisfy { $0 == 0 }, "Default cadence leaves quiet space after the tail")
            for interval in [1.0, 2, 7, 15, Double.nan] {
                let data = try SoundPlayer.wave(choice: .wood, interval: interval)
                let values = pcm(data)
                let expected = interval.isFinite ? interval : 2
                try expect(values.count == Int(expected * 44100), "Exact cadence even with overlapping decay")
                try expect(values.allSatisfy { abs($0) <= 29491 }, "Processed audio has headroom without clipping")
                try expect(abs(values.first! - values.last!) < 300, "No abrupt cut at the loop seam")
            }
            try expect(abs(wood.duration - 2) < 0.01 && abs(slow.duration - 7) < 0.01, "Wood spacing is reflected in decoded audio")
            try expect(wood.numberOfChannels == 1 && rain.numberOfChannels == 1 && rain.duration > 1, "Valid portable audio")
        }
        try check("Ambient recordings loop continuously; bell is reserved for completion") {
            for (choice, duration) in [(SoundChoice.bell, 19.0), (.pine, 32.0), (.rain, 24.0)] {
                let wave = try SoundPlayer.wave(choice: choice, interval: 2)
                let decoded = try AVAudioPlayer(data: wave, fileTypeHint: "wav")
                try expect(abs(decoded.duration - duration) < 0.02 && decoded.numberOfChannels == 1, "Bundled real recording decodes")
                func sample(_ offset: Int) -> Int {
                    Int(Int16(bitPattern: UInt16(wave[offset]) | (UInt16(wave[offset + 1]) << 8)))
                }
                if choice != .bell {
                    try expect(abs(sample(44) - sample(wave.count - 2)) < 3000, "Crossfade prevents a large loop-boundary jump")
                }
                let player = SoundPlayer()
                try player.play(choice: choice, volume: 0, interval: 2)
                if choice == .bell {
                    try expect(player.player == nil, "A legacy bell selection must not play as ambience")
                } else {
                    try expect(player.player?.numberOfLoops == -1 && player.player?.isPlaying == true, "All audible ambient choices loop")
                }
                player.stop()
            }
        }
        try check("Bell notification asset respects volume and legacy settings remain readable") {
            let folder = sandbox.appendingPathComponent("notification-sounds")
            let url = try SoundPlayer.installBellNotificationSound(volume: 0.35, directory: folder)
            let sound = try AVAudioPlayer(contentsOf: url)
            try expect(sound.duration > 10 && sound.duration < 30, "Notification sound meets the system duration limit")
            let original = try SoundPlayer.wave(choice: .bell, interval: 2)
            let quieter = try Data(contentsOf: url)
            try expect(original.count == quieter.count && original != quieter, "Volume is applied without trimming the decay")
            _ = try SoundPlayer.installBellNotificationSound(volume: 0, directory: folder)
            try expect(try Data(contentsOf: url).dropFirst(44).allSatisfy { $0 == 0 }, "Zero volume remains silent")
            var old = Preferences(); old.sound = .rain
            let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(old))
            try expect(restored.sound == .rain && restored.sound.title == "细雨", "Existing rain preference keeps working")
            old.sound = .bell; old.focusMinutes = 45; old.reminderVolume = 0.8
            let migrated = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(old)).normalized()
            try expect(migrated.sound == .silent && migrated.focusMinutes == 45 && migrated.completionVolume == 0.8, "Legacy bell ambience becomes silent without resetting other preferences")
            let session = ActiveSession(targetSeconds: 60)
            let restoredSession = try JSONDecoder().decode(ActiveSession.self, from: JSONEncoder().encode(session))
            try expect(restoredSession.soundChoice == nil && restoredSession.soundVolume == nil, "Old recovery files without sound snapshots decode")
        }
        try check("Native shortcut dispatch, conflict detection and cleanup") {
            _ = NSApplication.shared
            var settings = Preferences(); settings.startKey = 79; settings.abandonKey = 80
            settings.startModifiers = 6912; settings.abandonModifiers = 6912
            var shortcuts: GlobalShortcuts? = GlobalShortcuts(); try shortcuts!.register(settings)
            var challenger: GlobalShortcuts? = GlobalShortcuts()
            var conflictDetected = false
            do { try challenger!.register(settings) } catch { conflictDetected = true }
            try expect(conflictDetected, "Occupied shortcut must report conflict")
            challenger = nil
            var starts = 0; var abandons = 0
            shortcuts!.onStart = { starts += 1 }; shortcuts!.onAbandon = { abandons += 1 }
            for id in [UInt32(1), UInt32(2)] {
                var event: EventRef?
                try expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event) == noErr, "Native event creation")
                var hotkey = EventHotKeyID(signature: 0x5A454E31, id: id)
                SetEventParameter(event!, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &hotkey)
                SendEventToEventTarget(event!, GetApplicationEventTarget()); ReleaseEvent(event!)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            try expect(starts == 1 && abandons == 1, "Native events invoke the corresponding actions")
            shortcuts = nil
            let replacement = GlobalShortcuts(); try replacement.register(settings)
        }
        try check("Independent process SIGKILL preserves the persisted session checkpoint") {
            let (support, data) = try directories("process-crash")
            let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--crash-worker", support.path, data.path]
            try child.run(); child.waitUntilExit()
            try expect(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL, "Worker actually terminated abruptly")
            let persisted = try Journal(directory: support).load().active!
            let recovered = ZenModel(supportDirectory: support, servicesEnabled: false)
            try expect(recovered.active == nil && recovered.drafts.count == 1, "No resumed timer after a process crash")
            try expect(recovered.drafts[0].id == persisted.id && recovered.drafts[0].record.focusedSeconds == 5, "Same session and last checkpoint")
            recovered.saveAnnotation(persisted.id, skip: true)
            let again = ZenModel(supportDirectory: support, servicesEnabled: false)
            try expect(again.records.count == 1 && again.drafts.isEmpty, "Recovery retry does not duplicate records")
        }
        try check("Reminder settings are snapshotted with each session") {
            let (support, data) = try directories("reminder-settings")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.preferences.sound = .silent; model.preferences.volume = 0
            model.preferences.reminderVolume = 0.7
            model.start(continuousNow: 100)
            model.preferences.sound = .pine; model.preferences.volume = 0.5; model.preferences.reminderVolume = 0.3
            model.preferences.notificationEnabled = false; model.preferences.completionSound = false; model.savePreferences()
            try expect(model.active?.notificationEnabled == true && model.active?.completionSound == true, "Active reminder settings remain coherent")
            try expect(model.active?.soundChoice == .bell && model.active?.soundVolume == 0.7, "End bell retains this round's selection and volume")
            model.tick(at: 1600); model.start(continuousNow: 2000)
            try expect(model.active?.notificationEnabled == false && model.active?.completionSound == false, "Next session uses new reminder settings")
        }
        try check("Completion opens the just-finished entry once, including with notifications disabled") {
            let (support, data) = try directories("completion-prompt")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false); model.chooseDirectory(data)
            model.preferences.notificationEnabled = false; model.preferences.completionSound = false
            model.preferences.focusMinutes = 1; model.preferences.restMinutes = 1
            var opened = 0; model.openWindow = { opened += 1 }
            model.start(continuousNow: 100); let first = model.active!.id; model.tick(at: 160)
            try expect(model.editorID == first && model.selectedTab == 1 && opened == 1, "Automatically opens the completed round")
            model.editorID = nil; model.tick(at: 170)
            try expect(model.editorID == nil && opened == 1, "Dismissing is respected; future ticks do not nag")
            model.start(continuousNow: 200); let second = model.active!.id; model.tick(at: 260)
            try expect(model.editorID == second && opened == 2, "New completion selects the new round instead of an older draft")
            model.showRecord(first)
            try expect(model.editorID == first, "A notification routes to its exact record")
            model.editorID = nil; model.start(continuousNow: 300); model.abandon(at: 310)
            try expect(model.editorID == nil && opened == 3, "Abandon does not interrupt with a writing prompt")
            model.start(rest: true, continuousNow: 400); model.tick(at: 460)
            try expect(model.editorID == nil && opened == 3, "Rest does not create or show a focus annotation")
            model.showRecord(UUID())
            try expect(model.editorID == nil, "A stale notification never opens an unrelated draft")
        }
        try check("Independent reminder volume migrates and completion uses the long bell") {
            let settings = Preferences()
            var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
            old.removeValue(forKey: "reminderVolume"); old["sound"] = "silent"; old["volume"] = 0
            let restored = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: old)).normalized()
            try expect(restored.volume == 0 && restored.completionVolume == 0.65, "Silent background keeps an independently audible end reminder")
            let sound = SoundPlayer(); sound.completion(volume: 0.01)
            try expect(sound.player?.isPlaying == true && sound.player!.duration > 10, "Completion starts the audible bell player")
            sound.stop()
            var quiet = restored; quiet.reminderVolume = 0
            try expect(quiet.normalized().completionVolume == 0, "Explicitly muted reminder remains muted")
        }
        print("\(passed)/\(passed) application flow checks passed")
        if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > index + 1 {
            let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            _ = NSApplication.shared
            let (support, data) = try directories("preview")
            let model = ZenModel(supportDirectory: support, servicesEnabled: false)
            func render(_ name: String, annotationID: UUID? = nil) throws {
                let content: AnyView
                if let annotationID { content = AnyView(AnnotationView(model: model, id: annotationID)) }
                else { content = AnyView(ZenRootView(model: model).frame(width: 480, height: 720)) }
                let host = NSHostingView(rootView: content)
                let size = annotationID == nil ? NSSize(width: 480, height: 720) : host.fittingSize
                let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host; window.orderFront(nil)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure(description: "Image render failed") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(description: "PNG failed") }
                window.orderOut(nil)
                try png.write(to: output.appendingPathComponent(name + ".png"))
            }
            try render("welcome"); model.chooseDirectory(data); try render("ready")
            model.start(label: "阅读 · 留意每一个念头", continuousNow: 100); model.tick(at: 550); try render("focusing")
            model.openWindow = {}; model.tick(at: 1600); model.editorID = nil
            try render("annotation", annotationID: model.drafts[0].id)
            model.selectedTab = 1; try render("records")
            model.selectedTab = 2; try render("settings")
            try SoundPlayer.wave(choice: .wood, interval: 2).write(to: output.appendingPathComponent("wood.wav"))
            print("Rendered six native SwiftUI views and exported processed wood audio to \(output.path)")
        }
    }
}
