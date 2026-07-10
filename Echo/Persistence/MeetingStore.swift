import Foundation
import SwiftData

final class MeetingStore: ObservableObject {
    @Published private(set) var meetings: [Meeting] = []

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        reload()
    }

    func seedSampleDataIfNeeded() {
        guard meetings.isEmpty else { return }
        seedSampleData()
    }

    func reload() {
        var descriptor = FetchDescriptor<StoredMeeting>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        let stored = (try? modelContext.fetch(descriptor)) ?? []
        meetings = stored.map(Meeting.fromStored)
    }

    func saveMeeting(_ meeting: StoredMeeting) {
        modelContext.insert(meeting)
        persist()
    }

    func updateActionItem(meetingID: UUID, itemID: UUID, isCompleted: Bool) {
        guard let stored = fetchStoredMeeting(id: meetingID),
              let item = stored.actionItems.first(where: { $0.id == itemID }) else { return }
        item.isCompleted = isCompleted
        persist()
    }

    func updateSummary(meetingID: UUID, summary: String, actionItems: [ActionItem]) {
        guard let stored = fetchStoredMeeting(id: meetingID) else { return }
        stored.aiSummary = summary
        stored.actionItems = actionItems.map {
            StoredActionItem(id: $0.id, text: $0.text, isCompleted: $0.isCompleted, meeting: stored)
        }
        persist()
    }

    func deleteMeeting(id: UUID) {
        guard let stored = fetchStoredMeeting(id: id) else { return }
        modelContext.delete(stored)
        persist()
    }

    func meeting(id: UUID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    private func fetchStoredMeeting(id: UUID) -> StoredMeeting? {
        var descriptor = FetchDescriptor<StoredMeeting>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func persist() {
        do {
            try modelContext.save()
            reload()
        } catch {
            print("MeetingStore save error: \(error)")
        }
    }

    private func seedSampleData() {
        let calendar = Calendar.current
        let samples: [(Int, Int, Int, String, String, String, Int, String, [(String, Bool)])] = [
            (2026, 7, 7, "クライアントA 定例MTG", "来週までにモックアップを共有できればと…", "Google Meet", 45,
             "モックアップの共有スケジュールとレビュー体制について合意。デザイン確認は火曜に実施予定。",
             [("モックアップを金曜までに共有(話者A)", false), ("レビュー日程を火曜で調整(話者B)", true)]),
            (2026, 7, 3, "社内 デザインレビュー", "このモックアップの配色について話したいのですが…", "Google Meet", 28,
             "配色とタイポグラフィの方向性について議論。", []),
            (2026, 6, 28, "新規案件 ヒアリング", "まずは簡単なモックアップを見せていただき…", "Zoom", 52,
             "新規案件の要件とスケジュール感をヒアリング。", [])
        ]

        for sample in samples {
            let start = calendar.date(from: DateComponents(year: sample.0, month: sample.1, day: sample.2, hour: 14)) ?? .now
            let end = start.addingTimeInterval(TimeInterval(sample.6 * 60))
            let stored = StoredMeeting(
                title: sample.3,
                startedAt: start,
                endedAt: end,
                detectedSource: sample.5,
                aiSummary: sample.7,
                transcriptLines: TranscriptLine.sampleLines(for: sample.3).map {
                    StoredTranscriptLine(
                        speakerRaw: $0.speaker.rawValue,
                        text: $0.text,
                        isPartial: $0.isDimmed
                    )
                },
                actionItems: sample.8.map {
                    StoredActionItem(text: $0.0, isCompleted: $0.1)
                }
            )
            modelContext.insert(stored)
        }
        persist()
    }
}
