import Foundation

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) throws {
    if a != b { throw CheckFailure(description: "\(file):\(line): \(a) != \(b)") }
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    if !value { throw CheckFailure(description: "\(file):\(line): expected true") }
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) throws { try XCTAssertTrue(!value, file: file, line: line) }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) throws {
    do { _ = try value() } catch { return }
    throw CheckFailure(description: "\(file):\(line): expected an error")
}
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure(description: "Unexpected nil") }; return value
}
class XCTestCase {
    var cleanups: [() -> Void] = []
    func addTeardownBlock(_ block: @escaping () -> Void) { cleanups.append(block) }
    func tearDown() { cleanups.reversed().forEach { $0() }; cleanups.removeAll() }
}

@main struct CoreChecks {
    static func main() throws {
        let suite = ZenCoreTests()
        let checks: [(String, () throws -> Void)] = [
            ("Chinese, multiline and delimiters", suite.testChineseMultilineAndDelimiterRoundTrip),
            ("External plain text", suite.testHandEditedPlainTextIsReadable),
            ("Unknown format preservation", suite.testUnknownSchemaAndFieldsAreNotSilentlyDiscarded),
            ("Continuous time and completion cap", suite.testCompletedAndAbandonedSessionsUseContinuousElapsed),
            ("Midnight and time zone", suite.testStartDayAndOffsetSurviveMidnightAndTransfer),
            ("Idempotency and annotation", suite.testSaveRetryIsIdempotentAndEditKeepsID),
            ("Concurrent external edit and delete protection", suite.testExternalEditCannotBeOverwrittenOrDeleted),
            ("Duplicate IDs and conflicts", suite.testCopiesDeduplicateButConflictsRemainOnDisk),
            ("Unavailable directory", suite.testUnavailableDirectoryDoesNotGetRecreated),
            ("Corrupt file protection", suite.testCorruptExistingFileIsNeverOverwritten),
            ("Journal and multiple pending drafts", suite.testJournalRetainsMultiplePendingDraftsAndBaseline),
            ("Symlink protection", suite.testSymlinkCannotRedirectWritesOutsideSelectedDirectory),
            ("File transfer and independent editing", suite.testPortableFilesReadByAnotherStore)
        ]
        var failures: [String] = []
        for (name, run) in checks {
            do { try run(); print("PASS \(name)") }
            catch { failures.append("\(name): \(error)"); print("FAIL \(name): \(error)") }
            suite.tearDown()
        }
        print("\(checks.count - failures.count)/\(checks.count) core checks passed")
        if !failures.isEmpty { exit(1) }
    }
}
