import Foundation

struct SummaryService {
    func generateSummary(
        from lines: [TranscriptLine],
        apiKey: String?
    ) async -> (summary: String, actionItems: [ActionItem]) {
        let transcript = lines
            .filter { !$0.isDimmed }
            .map { "\($0.speaker.label): \($0.text)" }
            .joined(separator: "\n")

        guard !transcript.isEmpty else {
            return ("文字起こし内容が不足しているため要約を生成できませんでした。", [])
        }

        if let apiKey, !apiKey.isEmpty {
            if let aiResult = await generateWithOpenAI(transcript: transcript, apiKey: apiKey) {
                return aiResult
            }
        }

        return generateOffline(from: lines, transcript: transcript)
    }

    private func generateWithOpenAI(transcript: String, apiKey: String) async -> (summary: String, actionItems: [ActionItem])? {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return nil }

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    あなたは会議要約アシスタントです。JSONのみ返してください。
                    形式: {"summary":"...", "actionItems":[{"text":"...", "speaker":"話者A"}]}
                    """
                ],
                [
                    "role": "user",
                    "content": "以下の会議を要約してください:\n\(transcript)"
                ]
            ],
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return parseOpenAIResponse(data)
        } catch {
            return nil
        }
    }

    private func parseOpenAIResponse(_ data: Data) -> (summary: String, actionItems: [ActionItem])? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            let contentData = content.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
            let summary = json["summary"] as? String
        else { return nil }

        let items = (json["actionItems"] as? [[String: Any]] ?? []).compactMap { item -> ActionItem? in
            guard let text = item["text"] as? String else { return nil }
            let speaker = (item["speaker"] as? String).map { "(\($0))" } ?? ""
            return ActionItem(text: "\(text)\(speaker)")
        }

        return (summary, items)
    }

    private func generateOffline(
        from lines: [TranscriptLine],
        transcript: String
    ) -> (summary: String, actionItems: [ActionItem]) {
        let sentences = lines
            .filter { !$0.isDimmed }
            .map(\.text)
            .flatMap { $0.split(whereSeparator: { ".!?。！？".contains($0) }).map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let summary = sentences.prefix(3).joined(separator: "。")
        let finalSummary = summary.isEmpty
            ? "会議の要点を自動抽出しました。"
            : summary + (summary.hasSuffix("。") ? "" : "。")

        let actionKeywords = ["までに", "担当", "確認", "共有", "実施", "調整", "レビュー", "送る", "準備"]
        var actionItems: [ActionItem] = []

        for line in lines where !line.isDimmed {
            if actionKeywords.contains(where: { line.text.contains($0) }) {
                actionItems.append(ActionItem(text: "\(line.text)(\(line.speaker.label))"))
            }
        }

        if actionItems.isEmpty, let last = lines.last(where: { !$0.isDimmed }) {
            actionItems.append(ActionItem(text: "フォローアップ: \(last.text)(\(last.speaker.label))"))
        }

        return (finalSummary, Array(actionItems.prefix(5)))
    }
}
