import Foundation
import SwiftData

@Model
final class StoredMeeting {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var detectedSource: String?
    var aiSummary: String
    @Relationship(deleteRule: .cascade, inverse: \StoredTranscriptLine.meeting)
    var transcriptLines: [StoredTranscriptLine]
    @Relationship(deleteRule: .cascade, inverse: \StoredActionItem.meeting)
    var actionItems: [StoredActionItem]

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        detectedSource: String? = nil,
        aiSummary: String = "",
        transcriptLines: [StoredTranscriptLine] = [],
        actionItems: [StoredActionItem] = []
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.detectedSource = detectedSource
        self.aiSummary = aiSummary
        self.transcriptLines = transcriptLines
        self.actionItems = actionItems
    }
}

@Model
final class StoredTranscriptLine {
    var id: UUID
    var speakerRaw: String
    var text: String
    var isPartial: Bool
    var createdAt: Date
    var meeting: StoredMeeting?

    init(
        id: UUID = UUID(),
        speakerRaw: String,
        text: String,
        isPartial: Bool = false,
        createdAt: Date = .now,
        meeting: StoredMeeting? = nil
    ) {
        self.id = id
        self.speakerRaw = speakerRaw
        self.text = text
        self.isPartial = isPartial
        self.createdAt = createdAt
        self.meeting = meeting
    }

    var speaker: Speaker {
        Speaker(rawValue: speakerRaw) ?? .a
    }
}

@Model
final class StoredActionItem {
    var id: UUID
    var text: String
    var isCompleted: Bool
    var meeting: StoredMeeting?

    init(
        id: UUID = UUID(),
        text: String,
        isCompleted: Bool = false,
        meeting: StoredMeeting? = nil
    ) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.meeting = meeting
    }
}
