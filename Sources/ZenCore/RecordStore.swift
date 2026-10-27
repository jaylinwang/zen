import Foundation

public struct StoredRecord: Identifiable, Equatable {
    public var id: UUID { record.id }
    public var record: FocusRecord
    public var url: URL
    public var source: String
    public var copies: [URL]
}
public struct ScanResult {
    public var records: [StoredRecord] = []
    public var issues: [String] = []
    public var conflictingIDs: Set<UUID> = []
}
public struct RecordStore {
    public let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func scan() throws -> ScanResult {
        try checkRoot()
        let recordsURL = root.appendingPathComponent("records", isDirectory: true)
        guard FileManager.default.fileExists(atPath: recordsURL.path) else { return ScanResult() }
        try ensureNoSymlink(recordsURL)
        var result = ScanResult(); var grouped: [UUID: [StoredRecord]] = [:]
        guard let enumerator = FileManager.default.enumerator(at: recordsURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { url, error in
            result.issues.append("\(url.lastPathComponent)：\(error.localizedDescription)"); return true
        }) else { throw RecordError.unavailable("无法读取记录目录") }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); result.issues.append("跳过符号链接：\(url.lastPathComponent)"); continue }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            do {
                let source = try String(contentsOf: url, encoding: .utf8)
                let record = try MarkdownCodec.decode(source)
                grouped[record.id, default: []].append(StoredRecord(record: record, url: url, source: source, copies: []))
            } catch { result.issues.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
        }
        for (id, group) in grouped {
            let sorted = group.sorted { $0.url.path < $1.url.path }
            var first = sorted[0]
            first.copies = sorted.dropFirst().map(\.url)
            if sorted.contains(where: { $0.record != first.record }) {
                result.conflictingIDs.insert(id)
                result.issues.append("同一记录存在不同版本，请在文件中处理：\(id.uuidString.lowercased())")
            }
            result.records.append(first)
        }
        result.records.sort { $0.record.startedAt > $1.record.startedAt }
        return result
    }

    /// An expected snapshot is an optimistic lock. Never infer write authority from a parsed ID alone.
    @discardableResult public func save(_ record: FocusRecord, expected: StoredRecord? = nil) throws -> StoredRecord {
        try checkRoot()
        let source = try MarkdownCodec.encode(record)
        let current = try scan()
        guard !current.conflictingIDs.contains(record.id) else { throw RecordError.conflict(record.title) }
        let existing = current.records.first { $0.id == record.id }
        let url: URL
        if let expected {
            guard expected.id == record.id, let found = existing, found.url.standardizedFileURL.path == expected.url.standardizedFileURL.path,
                  found.source == expected.source else { throw RecordError.conflict(record.title) }
            guard found.copies.isEmpty else { throw RecordError.conflict("请先移除重复副本，再编辑这条记录") }
            url = expected.url
        } else {
            if let existing {
                guard existing.record == record else { throw RecordError.conflict(record.title) }
                return existing // Retry after a successful write but before journal cleanup.
            }
            url = root.appendingPathComponent(record.relativePath)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw RecordError.conflict("目标文件已存在且无法安全读取") }
        }
        try ensureNoSymlink(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
            do {
                try ensureNoSymlink(coordinated)
                if let expected {
                    let disk = try String(contentsOf: coordinated, encoding: .utf8)
                    guard disk == expected.source else { throw RecordError.conflict(record.title) }
                } else if FileManager.default.fileExists(atPath: coordinated.path) {
                    guard try String(contentsOf: coordinated, encoding: .utf8) == source else { throw RecordError.conflict(record.title) }
                    return
                }
                try Data(source.utf8).write(to: coordinated, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError { throw error }
        if let error = writeError { throw error }
        return StoredRecord(record: record, url: url, source: source, copies: [])
    }

    public func delete(_ expected: StoredRecord) throws {
        try checkRoot(); try ensureNoSymlink(expected.url)
        let current = try scan()
        guard let found = current.records.first(where: { $0.id == expected.id }),
              !current.conflictingIDs.contains(expected.id), found.source == expected.source,
              found.copies.isEmpty, found.url.standardizedFileURL.path == expected.url.standardizedFileURL.path else { throw RecordError.conflict("删除前发现记录已改变或有副本") }
        var coordinationError: NSError?; var deletionError: Error?
        NSFileCoordinator().coordinate(writingItemAt: expected.url, options: .forDeleting, error: &coordinationError) { url in
            do {
                guard try String(contentsOf: url, encoding: .utf8) == expected.source else { throw RecordError.conflict(expected.record.title) }
                try FileManager.default.removeItem(at: url)
            } catch { deletionError = error }
        }
        if let error = coordinationError { throw error }; if let error = deletionError { throw error }
    }

    private func checkRoot() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw RecordError.unavailable("数据目录已移动或不可用，请重新选择目录") }
    }
    private func ensureNoSymlink(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        guard normalized.path.hasPrefix(root.path + "/") else { throw RecordError.unavailable("文件不在所选目录内") }
        var current = normalized
        while current.path != root.path {
            if FileManager.default.fileExists(atPath: current.path) {
                if try current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw RecordError.unavailable("记录路径包含符号链接") }
            }
            current.deleteLastPathComponent()
        }
    }
}
