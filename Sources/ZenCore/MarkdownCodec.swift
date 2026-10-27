import Foundation

public enum RecordError: LocalizedError {
    case malformed(String), conflict(String), unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .malformed(let detail): return "记录格式无法安全读取：\(detail)"
        case .conflict(let detail): return "文件已有其他修改，未覆盖：\(detail)"
        case .unavailable(let detail): return "未保存：\(detail)"
        }
    }
}

public enum MarkdownCodec {
    // Escape only lines that could masquerade as a section delimiter; preserve ordinary prose.
    static func escape(_ s: String) -> String {
        s.components(separatedBy: "\n").map { line in
            line.hasPrefix("\\") || line.hasPrefix("#") ? "\\" + line : line
        }.joined(separator: "\n")
    }
    static func unescape(_ s: String) -> String {
        s.components(separatedBy: "\n").map { line in
            line.hasPrefix("\\\\") || line.hasPrefix("\\#") ? String(line.dropFirst()) : line
        }.joined(separator: "\n")
    }
    static func dateString(_ date: Date, offset: Int) -> String {
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(secondsFromGMT: offset)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
    static func date(_ string: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = f.date(from: string) { return result }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: string)
    }
    public static func encode(_ r: FocusRecord) throws -> String {
        try validate(r)
        let hour = DateFormatter(); hour.locale = Locale(identifier: "en_US_POSIX")
        hour.timeZone = TimeZone(secondsFromGMT: r.timeZoneOffset); hour.dateFormat = "HH:mm"
        return """
        ---
        schema_version: 1
        date: \(r.dayKey)
        ---

        ## \(hour.string(from: r.startedAt)) \(r.title)

        - id: \(r.id.uuidString.lowercased())
        - started_at: \(dateString(r.startedAt, offset: r.timeZoneOffset))
        - ended_at: \(dateString(r.endedAt, offset: r.timeZoneOffset))
        - target_seconds: \(r.targetSeconds)
        - focused_seconds: \(r.focusedSeconds)
        - outcome: \(r.outcome.rawValue)
        - annotation_status: \(r.annotationStatus.rawValue)
        - label_origin: \(r.labelOrigin.rawValue)
        - reference: \(try jsonString(r.reference))

        ### 内容

        \(escape(r.content))

        ### 备注

        \(escape(r.notes))
        """ + "\n"
    }
    static func jsonString(_ s: String) throws -> String {
        String(data: try JSONEncoder().encode(s), encoding: .utf8)!
    }
    public static func decode(_ source: String) throws -> FocusRecord {
        let s = source.replacingOccurrences(of: "\r\n", with: "\n")
        guard s.hasPrefix("---\nschema_version: 1\ndate: "),
              let contentRange = s.range(of: "\n### 内容\n\n"),
              let notesRange = s.range(of: "\n\n### 备注\n\n", range: contentRange.upperBound..<s.endIndex) else {
            throw RecordError.malformed("缺少版本、内容或备注区块")
        }
        let header = String(s[..<contentRange.lowerBound])
        let allowed: Set<String> = ["id", "started_at", "ended_at", "target_seconds", "focused_seconds", "outcome", "annotation_status", "label_origin", "reference"]
        var fields: [String: String] = [:]
        var front = 0; var headings = 0
        for line in header.components(separatedBy: "\n") {
            if line == "---" { front += 1; continue }
            if line.isEmpty { continue }
            if front == 1 && (line == "schema_version: 1" || line.hasPrefix("date: ")) { continue }
            if front == 2 && line.hasPrefix("## ") { headings += 1; continue }
            guard front == 2, line.hasPrefix("- "), let separator = line.range(of: ":") else { throw RecordError.malformed("未知字段或附加文字；保留原文件") }
            let key = String(line[line.index(line.startIndex, offsetBy: 2)..<separator.lowerBound])
            guard allowed.contains(key), fields[key] == nil else { throw RecordError.malformed("重复或未知字段 \(key)") }
            fields[key] = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        guard front == 2, headings == 1, fields.count == allowed.count,
              let id = UUID(uuidString: fields["id"] ?? ""),
              let start = date(fields["started_at"] ?? ""), let end = date(fields["ended_at"] ?? ""),
              let target = Int(fields["target_seconds"] ?? ""), let focused = Int(fields["focused_seconds"] ?? ""),
              let outcome = Outcome(rawValue: fields["outcome"] ?? ""),
              let status = AnnotationStatus(rawValue: fields["annotation_status"] ?? ""),
              let origin = LabelOrigin(rawValue: fields["label_origin"] ?? "") else { throw RecordError.malformed("必填字段无效") }
        let rawReference = fields["reference"] ?? ""
        let reference: String
        if rawReference.hasPrefix("\"") {
            guard let value = try? JSONDecoder().decode(String.self, from: Data(rawReference.utf8)) else { throw RecordError.malformed("资料链接") }
            reference = value
        } else { reference = rawReference }
        let startText = fields["started_at"]!
        let offset: Int
        if startText.hasSuffix("Z") { offset = 0 }
        else {
            let tail = String(startText.suffix(6)); let parts = tail.dropFirst().split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h <= 23, m <= 59,
                  tail.first == "+" || tail.first == "-" else { throw RecordError.malformed("时间偏移量") }
            offset = (tail.first == "-" ? -1 : 1) * (h * 3600 + m * 60)
        }
        let content = String(s[contentRange.upperBound..<notesRange.lowerBound])
        var notes = String(s[notesRange.upperBound...]); if notes.hasSuffix("\n") { notes.removeLast() }
        // Extra unescaped headings may be an external schema extension; refuse to rewrite them.
        guard !content.components(separatedBy: "\n").contains(where: { $0.hasPrefix("#") }),
              !notes.components(separatedBy: "\n").contains(where: { $0.hasPrefix("#") }) else { throw RecordError.malformed("正文标题需要以反斜线转义") }
        let r = FocusRecord(id: id, startedAt: start, endedAt: end, targetSeconds: target, focusedSeconds: focused,
                            outcome: outcome, annotationStatus: status, labelOrigin: origin,
                            content: unescape(content), notes: unescape(notes), reference: reference, timeZoneOffset: offset)
        try validate(r)
        guard s.components(separatedBy: "\n").contains("date: \(r.dayKey)") else { throw RecordError.malformed("归档日期与开始时间不符") }
        return r
    }
    static func validate(_ r: FocusRecord) throws {
        guard r.targetSeconds > 0, r.focusedSeconds >= 0, r.focusedSeconds <= r.targetSeconds,
              r.endedAt >= r.startedAt, abs(r.timeZoneOffset) < 86400,
              r.outcome != .completed || r.focusedSeconds == r.targetSeconds else { throw RecordError.malformed("时长或结束状态无效") }
    }
}
