import Foundation

enum Speaker: String, Codable {
    case a = "話者A"
    case b = "話者B"

    var label: String { rawValue }

    /// デュアルチャンネル時の補足ラベル
    var channelHint: String {
        switch self {
        case .a: return "自分"
        case .b: return "相手"
        }
    }

    mutating func toggle() {
        self = self == .a ? .b : .a
    }
}

struct TranscriptLine: Identifiable, Hashable {
    let id: UUID
    let speaker: Speaker
    let text: String
    let isDimmed: Bool

    init(id: UUID = UUID(), speaker: Speaker, text: String, isDimmed: Bool = false) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.isDimmed = isDimmed
    }

    static let floatingPanelSamples: [TranscriptLine] = sampleLines(for: "会議")

    static func sampleLines(for title: String) -> [TranscriptLine] {
        if title.contains("デザイン") {
            return [
                TranscriptLine(speaker: .a, text: "このモックアップの配色について話したいのですが…"),
                TranscriptLine(speaker: .b, text: "了解です。ブランドカラーを基準に調整しましょう。")
            ]
        }
        if title.contains("ヒアリング") {
            return [
                TranscriptLine(speaker: .a, text: "まずは簡単なモックアップを見せていただき…"),
                TranscriptLine(speaker: .b, text: "要件の優先度を整理していきたいです。")
            ]
        }
        return [
            TranscriptLine(speaker: .a, text: "来週の金曜までにモックアップを共有できればと思います。"),
            TranscriptLine(speaker: .b, text: "承知しました、その前に一度レビューの時間を…"),
            TranscriptLine(speaker: .a, text: "はい、火曜あたりで調整できますか", isDimmed: true)
        ]
    }
}

struct ActionItem: Identifiable, Hashable {
    let id: UUID
    var text: String
    var isCompleted: Bool

    init(id: UUID = UUID(), text: String, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
    }
}

struct Meeting: Identifiable, Hashable {
    let id: UUID
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let preview: String
    let durationMinutes: Int
    let hasSummary: Bool
    let dateRange: String
    let speakerCount: Int
    let aiSummary: String
    let actionItems: [ActionItem]
    let transcriptLines: [TranscriptLine]
    let detectedSource: String?

    var day: Int {
        Calendar.current.component(.day, from: startedAt)
    }

    var month: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: startedAt).uppercased()
    }

    static func fromStored(_ stored: StoredMeeting) -> Meeting {
        let lines = stored.transcriptLines
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                TranscriptLine(
                    id: $0.id,
                    speaker: $0.speaker,
                    text: $0.text,
                    isDimmed: $0.isPartial
                )
            }

        let end = stored.endedAt ?? stored.startedAt
        let duration = max(1, Int(end.timeIntervalSince(stored.startedAt) / 60))
        let speakers = Set(lines.map(\.speaker)).count

        return Meeting(
            id: stored.id,
            title: stored.title,
            startedAt: stored.startedAt,
            endedAt: stored.endedAt,
            preview: lines.last(where: { !$0.isDimmed })?.text ?? stored.aiSummary,
            durationMinutes: duration,
            hasSummary: !stored.aiSummary.isEmpty,
            dateRange: DateRangeFormatter.format(start: stored.startedAt, end: end),
            speakerCount: max(speakers, 1),
            aiSummary: stored.aiSummary,
            actionItems: stored.actionItems.map {
                ActionItem(id: $0.id, text: $0.text, isCompleted: $0.isCompleted)
            },
            transcriptLines: lines,
            detectedSource: stored.detectedSource
        )
    }
}

enum DateRangeFormatter {
    static func format(start: Date, end: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "yyyy年M月d日"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ja_JP")
        timeFormatter.dateFormat = "HH:mm"

        return "\(dateFormatter.string(from: start)) \(timeFormatter.string(from: start))–\(timeFormatter.string(from: end))"
    }
}
