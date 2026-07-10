import Foundation

struct NotionConfiguration: Sendable {
    let token: String
    let databaseID: String
    let titleProperty: String

    var isConfigured: Bool {
        !token.isEmpty && !databaseID.isEmpty
    }
}

struct NotionService {
    enum NotionError: LocalizedError {
        case notConfigured
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Notion の API トークンとデータベース ID を設定してください。"
            case .invalidResponse:
                return "Notion から無効な応答が返されました。"
            case .apiError(let message):
                return message
            }
        }
    }

    func exportMeeting(_ meeting: Meeting, configuration: NotionConfiguration) async throws -> URL {
        guard configuration.isConfigured else { throw NotionError.notConfigured }
        guard let url = URL(string: "https://api.notion.com/v1/pages") else {
            throw NotionError.invalidResponse
        }

        let transcript = meeting.transcriptLines
            .map { "\($0.speaker.label): \($0.text)" }
            .joined(separator: "\n")

        let actionText = meeting.actionItems.isEmpty
            ? "なし"
            : meeting.actionItems.map { "\($0.isCompleted ? "☑" : "☐") \($0.text)" }.joined(separator: "\n")

        let properties: [String: Any] = [
            configuration.titleProperty: [
                "title": [
                    ["text": ["content": meeting.title]]
                ]
            ]
        ]

        let children: [[String: Any]] = [
            heading("📅 会議情報"),
            paragraph("日時: \(meeting.dateRange)\n話者: \(meeting.speakerCount)名\nソース: \(meeting.detectedSource ?? "不明")"),
            heading("💡 AI要約"),
            paragraph(meeting.aiSummary.isEmpty ? "要約なし" : meeting.aiSummary),
            heading("✓ アクションアイテム"),
            paragraph(actionText),
            heading("📝 文字起こし全文"),
            paragraph(transcript.isEmpty ? "文字起こしなし" : transcript)
        ]

        let body: [String: Any] = [
            "parent": ["database_id": configuration.databaseID],
            "properties": properties,
            "children": children
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotionError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw NotionError.apiError(message ?? "HTTP \(http.statusCode)")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pageID = json["id"] as? String
        else {
            throw NotionError.invalidResponse
        }

        let pageURL = pageID.replacingOccurrences(of: "-", with: "")
        return URL(string: "https://www.notion.so/\(pageURL)")!
    }

    private func heading(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "heading_2",
            "heading_2": [
                "rich_text": [["type": "text", "text": ["content": text]]]
            ]
        ]
    }

    private func paragraph(_ text: String) -> [String: Any] {
        let chunks = text.chunked(maxLength: 1800)
        return [
            "object": "block",
            "type": "paragraph",
            "paragraph": [
                "rich_text": chunks.map { chunk in
                    ["type": "text", "text": ["content": chunk]]
                }
            ]
        ]
    }
}

private extension String {
    func chunked(maxLength: Int) -> [String] {
        guard count > maxLength else { return [self] }
        var result: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: maxLength, limitedBy: endIndex) ?? endIndex
            result.append(String(self[start..<end]))
            start = end
        }
        return result
    }
}
