import Foundation
import SwiftUI

enum Speaker: String, Codable, CaseIterable {
    case a = "話者A"
    case b = "話者B"
    case c = "話者C"
    case d = "話者D"
    case e = "話者E"
    case f = "話者F"
    case g = "話者G"
    case h = "話者H"

    var label: String { rawValue }

    static let remoteOrder: [Speaker] = [.b, .c, .d, .e, .f, .g, .h]

    /// デュアルチャンネル時の補足ラベル
    var channelHint: String {
        self == .a ? "自分" : "参加者"
    }

    var isSelf: Bool { self == .a }

    var color: Color {
        switch self {
        case .a: .echoSpeakerA
        case .b: .echoSpeakerB
        case .c: Color(red: 0.18, green: 0.72, blue: 0.45)
        case .d: Color(red: 0.58, green: 0.36, blue: 0.96)
        case .e: Color(red: 0.93, green: 0.30, blue: 0.55)
        case .f: Color(red: 0.98, green: 0.62, blue: 0.04)
        case .g: Color(red: 0.20, green: 0.78, blue: 0.85)
        case .h: Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }

    static func remoteSpeaker(at index: Int) -> Speaker {
        remoteOrder[min(max(0, index), remoteOrder.count - 1)]
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
