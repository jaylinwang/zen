import Foundation
import Combine
import ZenCore
#if os(macOS)
import AppKit
import ServiceManagement
#endif

@MainActor public final class ZenModel: ObservableObject {
    @Published public var preferences = Preferences()
    @Published public var directory: URL?
    @Published public var active: ActiveSession?
    @Published public var remaining = 0
    @Published public var records: [StoredRecord] = []
    @Published public var drafts: [EditDraft] = []
    @Published public var issues: [String] = []
    @Published public var conflicts: Set<UUID> = []
    @Published public var errorMessage: String?
    @Published public var notice: String?
    @Published public var selectedTab = 0
    @Published public var editorID: UUID?
    @Published public var recoveryHealthy = true
    @Published public var notificationStatus = "可在系统设置中管理通知权限"
    @Published public var shortcutError: String?
    @Published public var isPreviewingSound = false
    private let support: URL
    private let journal: Journal
    private let servicesEnabled: Bool
    private var state = RecoveryState()
    private var journalReadable = true
    private let audio = SoundPlayer()
    private let notifier = CompletionNotifier()
    private var timer: Timer?
    private var previewStop: Task<Void, Never>?
    private var securityURL: URL?
    private var lastCheckpoint = 0
    #if os(macOS)
    private var shortcuts: GlobalShortcuts?
    #endif
    public var openWindow: (() -> Void)?
    public var pendingCount: Int {
        Set(records.filter { $0.record.annotationStatus == .pending }.map(\.id) + drafts.map(\.id)).count
    }
    public var recentNames: [String] {
        var names: [String] = []
        for item in records where !item.record.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !names.contains(item.record.title) { names.append(item.record.title) }
            if names.count == 6 { break }
        }
        return names
    }
    public var canStart: Bool { directory != nil && active == nil && recoveryHealthy }
    public var todaySeconds: Int {
        records.filter { Calendar.current.isDateInToday($0.record.startedAt) && $0.record.outcome != .abandoned && !conflicts.contains($0.id) }.reduce(0) { $0 + $1.record.focusedSeconds }
    }

    public init(supportDirectory: URL? = nil, servicesEnabled: Bool = true) {
        self.support = supportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zen", isDirectory: true)
        self.journal = Journal(directory: support); self.servicesEnabled = servicesEnabled
        if let data = try? Data(contentsOf: support.appendingPathComponent("preferences.json")), let p = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = p.normalized() }
        restoreDirectory()
        do { state = try journal.load() } catch { journalReadable = false; recoveryHealthy = false; errorMessage = "恢复文件无法读取，已保留原文件。请先备份或检查 recovery.json：\(error.localizedDescription)" }
        drafts = state.drafts
        if let session = state.active, recoveryHealthy {
            #if os(iOS)
            if session.bootID != "unknown" && session.bootID == ContinuousTime.bootID && ContinuousTime.now >= session.continuousStart {
                active = session; remaining = session.remaining(at: ContinuousTime.now)
            } else { recoverInterrupted(session) }
            #else
            recoverInterrupted(session)
            #endif
        }
        refresh()
        if servicesEnabled {
            notifier.configure()
            notifier.onOpen = { [weak self] id in self?.tick(); self?.showRecord(id) }
            notifier.onStatus = { [weak self] message in self?.notificationStatus = message }
            #if os(macOS)
            let shortcuts = GlobalShortcuts(); self.shortcuts = shortcuts
            shortcuts.onStart = { [weak self] in self?.start() }
            shortcuts.onAbandon = { [weak self] in self?.abandon() }
            configureShortcuts()
            #endif
            timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
            tick()
            if active != nil { updateAudio() }
        }
    }
    private func restoreDirectory() {
        let bookmarkURL = support.appendingPathComponent("directory.bookmark")
        guard let data = try? Data(contentsOf: bookmarkURL) else { return }
        do {
            var stale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
            #endif
            let url = try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
            _ = url.startAccessingSecurityScopedResource(); securityURL = url
            directory = url.standardizedFileURL.resolvingSymlinksInPath()
            if stale { try persistBookmark(url) }
        } catch { errorMessage = "数据目录权限需要重新授权，请在设置中重新选择。" }
    }
    private func persistBookmark(_ url: URL) throws {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #endif
        let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try data.write(to: support.appendingPathComponent("directory.bookmark"), options: .atomic)
    }
    public func chooseDirectory(_ url: URL) {
        guard active == nil else { errorMessage = "请在本轮结束后更换目录。"; return }
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            _ = try RecordStore(root: url).scan()
            try persistBookmark(url)
            securityURL?.stopAccessingSecurityScopedResource()
            securityURL = accessed ? url : nil; directory = url.standardizedFileURL.resolvingSymlinksInPath()
            errorMessage = nil; notice = "已选择目录。历史文件不会自动迁移。"; refresh()
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }; errorMessage = error.localizedDescription
        }
    }
    public func refresh() {
        guard let directory else { return }
        do { let scan = try RecordStore(root: directory).scan(); records = scan.records; issues = scan.issues; conflicts = scan.conflictingIDs }
        catch { errorMessage = error.localizedDescription }
    }
    @discardableResult private func persist() -> Bool {
        guard journalReadable else {
            errorMessage = "原恢复文件无法读取，已保留。请先修复该文件并重新打开应用。"; return false
        }
        state.active = active; state.drafts = drafts
        do { try journal.save(state); recoveryHealthy = true; return true }
        catch { recoveryHealthy = false; errorMessage = "本机恢复草稿未保存：\(error.localizedDescription)"; return false }
    }
    public func savePreferences() {
        preferences = preferences.normalized()
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try JSONEncoder().encode(preferences).write(to: support.appendingPathComponent("preferences.json"), options: .atomic)
        } catch { errorMessage = "设置未保存：\(error.localizedDescription)" }
        updateAudio()
        #if os(macOS)
        configureShortcuts()
        #endif
    }
    public func start(label: String = "", rest: Bool = false, now: Date = Date(), continuousNow: TimeInterval = ContinuousTime.now) {
        guard canStart, let directory else {
            if directory == nil { selectedTab = 2; notice = "先选择一个存放记录的文件夹。"; openWindow?() }
            return
        }
        let session = ActiveSession(targetSeconds: (rest ? preferences.restMinutes : preferences.focusMinutes) * 60,
                                    label: label, isRest: rest, now: now, continuousNow: continuousNow,
                                    notificationEnabled: preferences.notificationEnabled, completionSound: preferences.completionSound,
                                    soundChoice: .bell, soundVolume: preferences.completionVolume)
        active = session; state.activeDirectory = directory.path; remaining = session.targetSeconds; lastCheckpoint = 0
        guard persist() else { active = nil; state.active = nil; state.activeDirectory = nil; remaining = 0; return }
        notice = nil; selectedTab = 0; stopPreview(); updateAudio()
        if servicesEnabled && preferences.notificationEnabled { notifier.schedule(session: session, sound: preferences.completionSound) }
    }
    public func tick(at continuousNow: TimeInterval = ContinuousTime.now) {
        guard var session = active else { return }
        remaining = session.remaining(at: continuousNow)
        if remaining == 0 { finish(.completed, elapsed: session.targetSeconds, recent: continuousNow - session.continuousStart - Double(session.targetSeconds) < 5); return }
        let elapsed = session.elapsed(at: continuousNow)
        if elapsed - lastCheckpoint >= 5 {
            session.checkpointSeconds = elapsed; active = session
            if persist() { lastCheckpoint = elapsed }
        }
    }
    public func abandon(at continuousNow: TimeInterval = ContinuousTime.now) {
        guard let session = active else { return }
        let elapsed = session.elapsed(at: continuousNow)
        finish(elapsed >= session.targetSeconds ? .completed : .abandoned, elapsed: elapsed)
    }
    private func finish(_ outcome: Outcome, elapsed: Int, recent: Bool = true) {
        guard let session = active else { return }
        if !session.isRest && outcome != .abandoned {
            let record = session.finished(outcome: outcome, elapsed: elapsed)
            drafts.removeAll { $0.id == record.id }
            drafts.append(EditDraft(record: record, directoryPath: state.activeDirectory ?? directory?.path ?? ""))
        }
        active = nil; state.activeDirectory = nil
        // Ending a session is irreversible even when local recovery storage is unavailable.
        // Completed sessions retain their draft; abandoned sessions retain no time record.
        // Block new sessions until the cleared running state is saved successfully.
        let durable = persist()
        remaining = 0
        audio.stop(); isPreviewingSound = false
        if outcome != .completed && servicesEnabled { notifier.cancel(session.id) }
        if outcome == .completed && servicesEnabled {
            notifier.complete(session: session, recent: recent) { [weak self] in
                guard let self, self.active == nil else { return }
                self.audio.completion(volume: session.soundVolume ?? self.preferences.completionVolume)
            }
        }
        if session.isRest { notice = outcome == .completed ? "歇息结束。准备好时，再开始。" : "歇息已结束。"; return }
        if outcome == .abandoned {
            notice = "本轮已放弃，不留记录。"
            return
        }
        if durable { _ = writeDraft(session.id, finalize: false) }
        notice = "这一段时间已结束。留一句话，记下刚才。"
        if outcome == .completed { showRecord(session.id) }
    }
    private func recoverInterrupted(_ session: ActiveSession) {
        if servicesEnabled { notifier.cancel(session.id) }
        if !session.isRest {
            let r = session.finished(outcome: .interrupted, elapsed: session.checkpointSeconds)
            if !drafts.contains(where: { $0.id == r.id }) { drafts.append(EditDraft(record: r, directoryPath: state.activeDirectory ?? directory?.path ?? "")) }
        }
        active = nil; state.activeDirectory = nil
        if persist() { notice = "已保留上次异常中断前的检查点，没有续接计时。" }
    }
    public func beginEditing(_ record: StoredRecord) {
        guard !conflicts.contains(record.id) else { errorMessage = "这条记录存在不同版本，请先在文件中处理冲突。"; return }
        if !drafts.contains(where: { $0.id == record.id }) {
            drafts.append(EditDraft(record: record.record, expected: record, directoryPath: directory?.path ?? ""))
            guard persist() else { return }
        }
        editorID = record.id
    }
    public func showRecord(_ id: UUID) {
        if drafts.contains(where: { $0.id == id }) { editorID = id }
        else if let saved = records.first(where: { $0.id == id }) { beginEditing(saved) }
        else { return }
        selectedTab = 1
        openWindow?()
    }
    public func showPending() {
        selectedTab = 1
        if let draft = drafts.first { editorID = draft.id }
        else if let first = records.first(where: { $0.record.annotationStatus == .pending }) { beginEditing(first) }
        openWindow?()
    }
    public func updateDraft(_ draft: EditDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index] = draft; _ = persist()
    }
    public func saveAnnotation(_ id: UUID, skip: Bool = false) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        let r = drafts[index].record
        drafts[index].record = r.annotated(content: r.content, notes: r.notes, reference: r.reference, skip: skip)
        guard persist() else { return }
        if writeDraft(id, finalize: true) { editorID = nil; notice = "已保存到本地。" }
    }
    @discardableResult public func retryDraft(_ id: UUID) -> Bool { writeDraft(id, finalize: true) }
    @discardableResult private func writeDraft(_ id: UUID, finalize: Bool) -> Bool {
        guard let directory, let index = drafts.firstIndex(where: { $0.id == id }) else { return false }
        let draft = drafts[index]
        guard draft.directoryPath == directory.path else {
            errorMessage = "这份草稿属于原目录。请重新选择原目录，或在草稿中明确选择保存到当前目录。"; return false
        }
        do {
            let store = RecordStore(root: directory)
            let saved: StoredRecord
            // A write may have succeeded before a crash prevented clearing the journal.
            let scan = try store.scan()
            if !scan.conflictingIDs.contains(id), let existing = scan.records.first(where: { $0.id == id && $0.record == draft.record }) { saved = existing }
            else { saved = try store.save(draft.record, expected: draft.expected) }
            let backup = drafts
            if finalize { drafts.removeAll { $0.id == id } }
            else { drafts[index] = EditDraft(record: saved.record, expected: saved, directoryPath: directory.path) }
            if !persist() { drafts = backup; return false }
            errorMessage = nil; refresh(); return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    public func moveDraftToCurrentDirectory(_ id: UUID) {
        guard let directory, let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].directoryPath = directory.path; drafts[index].expectedSource = nil; drafts[index].expectedPath = nil
        _ = persist()
    }
    public func retryRecovery() {
        if persist() { errorMessage = nil; notice = "本机恢复草稿已保存。" }
    }
    public func deleteRecord(_ id: UUID) {
        guard let directory else { return }
        if let draft = drafts.first(where: { $0.id == id }), draft.directoryPath != directory.path {
            errorMessage = "请先选择这份草稿所属的原目录，再删除记录。"; return
        }
        let previousDrafts = drafts
        do {
            let scan = try RecordStore(root: directory).scan()
            let draft = drafts.first(where: { $0.id == id })
            let saved = scan.records.first(where: { $0.id == id })
            guard draft != nil || saved != nil else { return }
            if saved == nil, let path = draft?.expectedPath, FileManager.default.fileExists(atPath: path) {
                throw RecordError.conflict("原文件无法安全读取，保留文件和草稿")
            }
            // Clear recovery first: failure leaves the official file untouched; a crash before
            // file deletion only leaves a record visible, never a resurrectable stale draft.
            drafts.removeAll { $0.id == id }
            guard persist() else { drafts = previousDrafts; return }
            if let saved { try RecordStore(root: directory).delete(draft?.expected ?? saved) }
            editorID = nil; errorMessage = nil; refresh()
        } catch {
            drafts = previousDrafts; _ = persist()
            errorMessage = error.localizedDescription
        }
    }
    public func requestNotifications() async {
        guard servicesEnabled else { return }
        do { let allowed = try await notifier.requestPermission(); notificationStatus = allowed ? "通知已允许" : "通知未允许，可在系统设置中开启" }
        catch { notificationStatus = error.localizedDescription }
    }
    public func previewSound() {
        guard active == nil else { return }
        isPreviewingSound = true; updateAudio(); previewStop?.cancel()
        previewStop = Task { try? await Task.sleep(nanoseconds: 10_000_000_000); if !Task.isCancelled { self.stopPreview() } }
    }
    public func stopPreview() { previewStop?.cancel(); isPreviewingSound = false; if active == nil { audio.stop() } }
    private func updateAudio() {
        guard servicesEnabled else { return }
        guard (active != nil && active?.isRest == false) || isPreviewingSound else { audio.stop(); return }
        do { try audio.play(choice: preferences.sound, volume: preferences.volume, interval: preferences.woodInterval) }
        catch { errorMessage = "计时仍在继续。声音未能播放：\(error.localizedDescription)" }
    }
    #if os(macOS)
    private func configureShortcuts() {
        guard servicesEnabled else { return }
        do { try shortcuts?.register(preferences); shortcutError = nil }
        catch { shortcutError = error.localizedDescription }
    }
    public var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public func setLoginEnabled(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; objectWillChange.send() }
        catch { errorMessage = "开机启动设置失败：\(error.localizedDescription)" }
    }
    public func revealDirectory() { if let directory { NSWorkspace.shared.open(directory) } }
    #endif
}
