import Foundation
import ZenCore

final class ZenCoreTests: XCTestCase {
    func record() -> FocusRecord {
        FocusRecord(startedAt: Date(timeIntervalSince1970: 1792537200), endedAt: Date(timeIntervalSince1970: 1792538700),
                    targetSeconds: 1500, focusedSeconds: 1500, outcome: .completed, timeZoneOffset: 28800)
    }
    func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testChineseMultilineAndDelimiterRoundTrip() throws {
        var r = record(); r.content = "写中文\n### 备注\n\\原样\n🙂\n"; r.notes = "\n## 标题\n- id: fake\n\n"; r.reference = "路径\n\"quote\"\\test"
        try XCTAssertEqual(try MarkdownCodec.decode(MarkdownCodec.encode(r)), r)
    }
    func testHandEditedPlainTextIsReadable() throws {
        let s = try MarkdownCodec.encode(record()).replacingOccurrences(of: "### 内容\n\n\n", with: "### 内容\n\n读了一页书\n")
        try XCTAssertEqual(try MarkdownCodec.decode(s).content, "读了一页书")
    }
    func testUnknownSchemaAndFieldsAreNotSilentlyDiscarded() throws {
        let s = try MarkdownCodec.encode(record())
        try XCTAssertThrowsError(try MarkdownCodec.decode(s.replacingOccurrences(of: "schema_version: 1", with: "schema_version: 2")))
        try XCTAssertThrowsError(try MarkdownCodec.decode(s.replacingOccurrences(of: "- id:", with: "用户自定义文字\n- id:")))
        try XCTAssertThrowsError(try MarkdownCodec.decode(s.replacingOccurrences(of: "focused_seconds: 1500", with: "focused_seconds: -1")))
    }
    func testCompletedAndAbandonedSessionsUseContinuousElapsed() throws {
        let start = Date(timeIntervalSince1970: 10000)
        let session = ActiveSession(targetSeconds: 1500, now: start, continuousNow: 10, bootID: "test")
        try XCTAssertEqual(session.elapsed(at: 10 + 480), 480)
        try XCTAssertEqual(session.finished(outcome: .abandoned, elapsed: 480).focusedSeconds, 480)
        try XCTAssertEqual(session.elapsed(at: 9999), 1500)
        let done = session.finished(outcome: .completed, elapsed: 9999)
        try XCTAssertEqual(done.endedAt, start.addingTimeInterval(1500))
        try XCTAssertEqual(done.focusedSeconds, 1500)
    }
    func testStartDayAndOffsetSurviveMidnightAndTransfer() throws {
        var r = record()
        r.startedAt = ISO8601DateFormatter().date(from: "2026-10-21T23:55:00+08:00")!
        r.endedAt = r.startedAt.addingTimeInterval(1500)
        try XCTAssertEqual(r.dayKey, "2026-10-21")
        try XCTAssertTrue(r.relativePath.contains("2026/10/2026-10-21/"))
        try XCTAssertEqual(try MarkdownCodec.decode(MarkdownCodec.encode(r)).dayKey, r.dayKey)
    }
    func testSaveRetryIsIdempotentAndEditKeepsID() throws {
        let store = RecordStore(root: try temp()); let r = record()
        let initial = try store.save(r); _ = try store.save(r)
        try XCTAssertEqual(try store.scan().records.count, 1)
        let changed = r.annotated(content: "写完一个函数", notes: "", reference: "")
        _ = try store.save(changed, expected: initial)
        try XCTAssertEqual(try store.scan().records.first?.record, changed)
        try XCTAssertThrowsError(try store.save(r))
    }
    func testExternalEditCannotBeOverwrittenOrDeleted() throws {
        let store = RecordStore(root: try temp()); let r = record(); let snapshot = try store.save(r)
        let external = r.annotated(content: "另一台设备补记", notes: "", reference: "")
        try MarkdownCodec.encode(external).write(to: snapshot.url, atomically: true, encoding: .utf8)
        try XCTAssertThrowsError(try store.save(r.annotated(content: "本地编辑", notes: "", reference: ""), expected: snapshot))
        try XCTAssertThrowsError(try store.delete(snapshot))
        try XCTAssertEqual(try store.scan().records.first?.record, external)
    }
    func testCopiesDeduplicateButConflictsRemainOnDisk() throws {
        let root = try temp(); let store = RecordStore(root: root); let r = record(); let first = try store.save(r)
        let copy = first.url.deletingLastPathComponent().appendingPathComponent("copy.md")
        try FileManager.default.copyItem(at: first.url, to: copy)
        try XCTAssertEqual(try store.scan().records.count, 1)
        try XCTAssertTrue(try store.scan().conflictingIDs.isEmpty)
        try MarkdownCodec.encode(r.annotated(content: "不同版本", notes: "", reference: "")).write(to: copy, atomically: true, encoding: .utf8)
        try XCTAssertEqual(try store.scan().conflictingIDs, [r.id])
        try XCTAssertThrowsError(try store.save(r, expected: first))
        try XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }
    func testUnavailableDirectoryDoesNotGetRecreated() throws {
        let root = try temp().appendingPathComponent("missing")
        try XCTAssertThrowsError(try RecordStore(root: root).save(record()))
        try XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
    func testCorruptExistingFileIsNeverOverwritten() throws {
        let store = RecordStore(root: try temp()); let r = record(); let saved = try store.save(r)
        try "broken".write(to: saved.url, atomically: true, encoding: .utf8)
        try XCTAssertThrowsError(try store.save(r))
        try XCTAssertEqual(try String(contentsOf: saved.url), "broken")
    }
    func testJournalRetainsMultiplePendingDraftsAndBaseline() throws {
        let dir = try temp(); let store = RecordStore(root: dir); let saved = try store.save(record())
        var state = RecoveryState(); state.active = ActiveSession(targetSeconds: 60, continuousNow: 50)
        state.drafts = [EditDraft(record: saved.record, expected: saved, directoryPath: dir.path), EditDraft(record: record(), directoryPath: dir.path)]
        let journal = Journal(directory: try temp()); try journal.save(state)
        let restored = try journal.load(); try XCTAssertEqual(restored, state)
        try XCTAssertEqual(restored.drafts.first?.expected?.source, saved.source)
    }
    func testSymlinkCannotRedirectWritesOutsideSelectedDirectory() throws {
        let root = try temp(); let outside = try temp()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("records"), withDestinationURL: outside)
        try XCTAssertThrowsError(try RecordStore(root: root).save(record()))
        try XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path).count, 0)
    }
    func testPortableFilesReadByAnotherStore() throws {
        let firstRoot = try temp(); let secondRoot = try temp(); let a = RecordStore(root: firstRoot); let b = RecordStore(root: secondRoot)
        let r = record(); _ = try a.save(r)
        try FileManager.default.copyItem(at: firstRoot.appendingPathComponent("records"), to: secondRoot.appendingPathComponent("records"))
        let imported = try XCTUnwrap(b.scan().records.first)
        try XCTAssertEqual(imported.record, r)
        _ = try b.save(r.annotated(content: "手机补记", notes: "", reference: ""), expected: imported)
        try XCTAssertEqual(try a.scan().records.first?.record, r)
    }
}
