import Foundation

public struct EditDraft: Codable, Identifiable, Equatable {
    public var id: UUID { record.id }
    public var record: FocusRecord
    public var expectedSource: String?
    public var expectedPath: String?
    public var directoryPath: String
    public init(record: FocusRecord, expected: StoredRecord? = nil, directoryPath: String) {
        self.record = record; self.expectedSource = expected?.source; self.expectedPath = expected?.url.path; self.directoryPath = directoryPath
    }
    public var expected: StoredRecord? {
        guard let source = expectedSource, let path = expectedPath, let record = try? MarkdownCodec.decode(source) else { return nil }
        return StoredRecord(record: record, url: URL(fileURLWithPath: path), source: source, copies: [])
    }
}
public struct RecoveryState: Codable, Equatable {
    public var active: ActiveSession?
    public var activeDirectory: String?
    public var drafts: [EditDraft] = []
    public init() {}
}

public struct Journal {
    public let url: URL
    public init(directory: URL) { self.url = directory.appendingPathComponent("recovery.json") }
    public func load() throws -> RecoveryState {
        guard FileManager.default.fileExists(atPath: url.path) else { return RecoveryState() }
        return try JSONDecoder().decode(RecoveryState.self, from: Data(contentsOf: url))
    }
    public func save(_ state: RecoveryState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

public enum SoundChoice: String, Codable, CaseIterable {
    case silent, wood, bell, pine, rain
    // Keep bell decodable for old settings and recovery files; it is no longer an ambience.
    public static let ambientChoices: [SoundChoice] = [.silent, .wood, .pine, .rain]
    public var title: String { switch self { case .silent: return "静音"; case .wood: return "木鱼"; case .bell: return "磬声"; case .pine: return "松风"; case .rain: return "细雨" } }
}
public struct Preferences: Codable, Equatable {
    public var focusMinutes: Int = 25
    public var restMinutes: Int = 5
    public var sound: SoundChoice = .wood
    public var volume: Double = 0.35
    public var woodInterval: Double = 2
    public var soundDefaultsVersion: Int? = 1
    public var notificationEnabled: Bool = true
    public var completionSound: Bool = true
    public var reminderVolume: Double? = 0.65
    public var completionVolume: Double { reminderVolume ?? 0.65 }
    public var startKey: UInt32 = 49 // Space
    public var startModifiers: UInt32 = 6144 // control + option
    public var abandonKey: UInt32 = 53 // Escape
    public var abandonModifiers: UInt32 = 6144
    public init() {}
    public func normalized() -> Preferences {
        var p = self
        if p.sound == .bell { p.sound = .silent }
        if p.soundDefaultsVersion == nil && p.woodInterval == 3 { p.woodInterval = 2 }
        p.soundDefaultsVersion = 1
        p.focusMinutes = max(1, min(240, p.focusMinutes)); p.restMinutes = max(1, min(60, p.restMinutes))
        p.volume = p.volume.isFinite ? max(0, min(1, p.volume)) : 0.35
        p.reminderVolume = p.completionVolume.isFinite ? max(0, min(1, p.completionVolume)) : 0.65
        p.woodInterval = p.woodInterval.isFinite ? max(1, min(15, p.woodInterval)) : 2
        return p
    }

}
