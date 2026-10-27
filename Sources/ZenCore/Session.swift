import Foundation
import Darwin

public enum Outcome: String, Codable, CaseIterable {
    case completed, abandoned, interrupted
    public var title: String {
        switch self { case .completed: return "已完成"; case .abandoned: return "已放弃"; case .interrupted: return "异常中断" }
    }
}
public enum AnnotationStatus: String, Codable { case pending, recorded, skipped }
public enum LabelOrigin: String, Codable { case before_session, after_session, none }

public struct FocusRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var targetSeconds: Int
    public var focusedSeconds: Int
    public var outcome: Outcome
    public var annotationStatus: AnnotationStatus
    public var labelOrigin: LabelOrigin
    public var content: String
    public var notes: String
    public var reference: String
    public var timeZoneOffset: Int

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, targetSeconds: Int, focusedSeconds: Int,
                outcome: Outcome, annotationStatus: AnnotationStatus = .pending, labelOrigin: LabelOrigin = .none,
                content: String = "", notes: String = "", reference: String = "", timeZoneOffset: Int? = nil) {
        self.id = id
        self.startedAt = Date(timeIntervalSince1970: (startedAt.timeIntervalSince1970 * 1000).rounded() / 1000)
        self.endedAt = Date(timeIntervalSince1970: (endedAt.timeIntervalSince1970 * 1000).rounded() / 1000)
        self.targetSeconds = targetSeconds; self.focusedSeconds = focusedSeconds
        self.outcome = outcome; self.annotationStatus = annotationStatus; self.labelOrigin = labelOrigin
        self.content = content; self.notes = notes; self.reference = reference
        self.timeZoneOffset = timeZoneOffset ?? TimeZone.current.secondsFromGMT(for: startedAt)
    }
    public var title: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? "未命名专注"
    }
    public var dayKey: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: timeZoneOffset); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: startedAt)
    }
    public var relativePath: String {
        "records/\(dayKey.prefix(4))/\(dayKey.dropFirst(5).prefix(2))/\(dayKey)/\(id.uuidString.lowercased()).md"
    }
    public func annotated(content: String, notes: String, reference: String, skip: Bool = false) -> FocusRecord {
        var r = self; r.content = content; r.notes = notes; r.reference = reference
        r.annotationStatus = skip ? .skipped : .recorded
        if r.labelOrigin == .none && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { r.labelOrigin = .after_session }
        return r
    }
}

public enum ContinuousTime {
    /// Includes sleep, unlike process uptime. Values are comparable across processes in one boot.
    public static var now: TimeInterval { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000 }
    public static var bootID: String {
        var value = timeval(); var size = MemoryLayout<timeval>.size
        let result = sysctlbyname("kern.boottime", &value, &size, nil, 0)
        return result == 0 ? "\(value.tv_sec):\(value.tv_usec)" : "unknown"
    }
}

public struct ActiveSession: Codable, Equatable {
    public var id: UUID
    public var startedAt: Date
    public var continuousStart: TimeInterval
    public var bootID: String
    public var targetSeconds: Int
    public var label: String
    public var isRest: Bool
    public var timeZoneOffset: Int
    public var checkpointSeconds: Int = 0
    public var notificationEnabled: Bool?
    public var completionSound: Bool?
    public var soundChoice: SoundChoice?
    public var soundVolume: Double?
    public init(targetSeconds: Int, label: String = "", isRest: Bool = false, now: Date = Date(),
                continuousNow: TimeInterval = ContinuousTime.now, bootID: String = ContinuousTime.bootID,
                notificationEnabled: Bool? = nil, completionSound: Bool? = nil,
                soundChoice: SoundChoice? = nil, soundVolume: Double? = nil) {
        self.id = UUID(); self.startedAt = now; self.continuousStart = continuousNow; self.bootID = bootID
        self.targetSeconds = max(1, targetSeconds); self.label = label; self.isRest = isRest
        self.timeZoneOffset = TimeZone.current.secondsFromGMT(for: now)
        self.notificationEnabled = notificationEnabled; self.completionSound = completionSound
        self.soundChoice = soundChoice; self.soundVolume = soundVolume
    }
    public func elapsed(at continuousNow: TimeInterval) -> Int {
        let delta = continuousNow - continuousStart
        guard delta.isFinite else { return 0 }
        return Int(min(Double(targetSeconds), max(0, delta.rounded(.down))))
    }
    public func remaining(at continuousNow: TimeInterval) -> Int { max(0, targetSeconds - elapsed(at: continuousNow)) }
    public func finished(outcome: Outcome, elapsed: Int) -> FocusRecord {
        let seconds = outcome == .completed ? targetSeconds : min(targetSeconds, max(0, elapsed))
        return FocusRecord(id: id, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(Double(seconds)),
                           targetSeconds: targetSeconds, focusedSeconds: seconds, outcome: outcome,
                           labelOrigin: label.isEmpty ? .none : .before_session, content: label, timeZoneOffset: timeZoneOffset)
    }
}

public func durationText(_ seconds: Int) -> String {
    String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
}
