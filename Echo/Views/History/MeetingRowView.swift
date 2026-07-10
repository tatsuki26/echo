import SwiftUI

struct MeetingRowView: View {
    let meeting: Meeting
    let isSelected: Bool
    let highlightTerm: String

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Text("\(meeting.day)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.echoTextPrimary)
                Text(meeting.month)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.echoTextTertiary)
                    .textCase(.uppercase)
            }
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.echoTextPrimary)
                    .lineLimit(1)

                HighlightedText(
                    text: meeting.preview,
                    highlight: highlightTerm,
                    font: .system(size: 12),
                    baseColor: .echoTextSecondary
                )
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(meeting.durationMinutes)分")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.echoTextTertiary)

                if meeting.hasSummary {
                    Text("要約あり")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.echoAccentTeal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.echoAccentTeal.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.echoAccent.opacity(0.08)
        }
        if isHovered {
            return Color.echoBgPage
        }
        return .clear
    }
}

struct HighlightedText: View {
    let text: String
    let highlight: String
    let font: Font
    let baseColor: Color

    var body: some View {
        if highlight.isEmpty || !text.localizedCaseInsensitiveContains(highlight) {
            Text(text)
                .font(font)
                .foregroundStyle(baseColor)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(splitParts().enumerated()), id: \.offset) { _, part in
                    if part.isMatch {
                        Text(part.text)
                            .font(font)
                            .foregroundStyle(baseColor)
                            .background(Color.echoHighlight)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    } else {
                        Text(part.text)
                            .font(font)
                            .foregroundStyle(baseColor)
                    }
                }
            }
        }
    }

    private struct TextPart {
        let text: String
        let isMatch: Bool
    }

    private func splitParts() -> [TextPart] {
        var parts: [TextPart] = []
        var currentIndex = text.startIndex
        let lowerText = text.lowercased()
        let lowerHighlight = highlight.lowercased()

        while let range = lowerText.range(of: lowerHighlight, range: currentIndex..<text.endIndex) {
            if currentIndex < range.lowerBound {
                parts.append(TextPart(text: String(text[currentIndex..<range.lowerBound]), isMatch: false))
            }
            parts.append(TextPart(text: String(text[range]), isMatch: true))
            currentIndex = range.upperBound
        }

        if currentIndex < text.endIndex {
            parts.append(TextPart(text: String(text[currentIndex...]), isMatch: false))
        }

        return parts
    }
}
