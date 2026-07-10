import AppKit
import Foundation
import UniformTypeIdentifiers

enum MeetingExportService {
    static func markdown(for meeting: Meeting) -> String {
        var lines: [String] = []
        lines.append("# \(meeting.title)")
        lines.append("")
        lines.append("- 日時: \(meeting.dateRange)")
        lines.append("- 所要時間: \(meeting.durationMinutes)分")
        if let source = meeting.detectedSource {
            lines.append("- ソース: \(source)")
        }
        lines.append("")

        if !meeting.aiSummary.isEmpty {
            lines.append("## AI要約")
            lines.append("")
            lines.append(meeting.aiSummary)
            lines.append("")
        }

        if !meeting.actionItems.isEmpty {
            lines.append("## アクションアイテム")
            lines.append("")
            for item in meeting.actionItems {
                let mark = item.isCompleted ? "[x]" : "[ ]"
                lines.append("- \(mark) \(item.text)")
            }
            lines.append("")
        }

        if !meeting.transcriptLines.isEmpty {
            lines.append("## 文字起こし全文")
            lines.append("")
            for line in meeting.transcriptLines where !line.isDimmed {
                lines.append("**\(line.speaker.label)**: \(line.text)")
            }
            lines.append("")
        }

        lines.append("---")
        lines.append("Exported by Echo")
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func exportViaSavePanel(meeting: Meeting) -> URL? {
        let panel = NSSavePanel()
        panel.title = "会議をエクスポート"
        panel.nameFieldStringValue = sanitizedFilename(meeting.title) + ".md"
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try markdown(for: meeting).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Echo export error: \(error)")
            return nil
        }
    }

    private static func sanitizedFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return title
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
            .description
    }
}
