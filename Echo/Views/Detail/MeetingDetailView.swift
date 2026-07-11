import SwiftUI

struct MeetingDetailView: View {
    @EnvironmentObject private var appState: AppState
    let meeting: Meeting

    @State private var actionItems: [ActionItem]

    init(meeting: Meeting) {
        self.meeting = meeting
        _actionItems = State(initialValue: meeting.actionItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            content
            footer
        }
        .background(Color.echoBgPanel)
        .onChange(of: meeting.actionItems) { _, newValue in
            actionItems = newValue
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.echoTextPrimary)

            Text("\(meeting.dateRange) · 話者\(meeting.speakerCount)名")
                .font(.system(size: 11))
                .foregroundStyle(Color.echoTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { EchoDivider() }
    }

    private var tabs: some View {
        HStack(spacing: 16) {
            ForEach(MeetingDetailTab.allCases, id: \.self) { tab in
                Button {
                    appState.selectedTab = tab
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                appState.selectedTab == tab ? Color.echoTextPrimary : Color.echoTextTertiary
                            )

                        Rectangle()
                            .fill(appState.selectedTab == tab ? Color.echoAccent : Color.clear)
                            .frame(height: 2)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { EchoDivider() }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if appState.selectedTab == .summary {
                    SummaryBox(
                        label: "💡 AI要約",
                        content: {
                            Text(meeting.aiSummary.isEmpty ? "要約を生成中、または未生成です。" : meeting.aiSummary)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.echoTextPrimary)
                                .lineSpacing(6)
                        }
                    )

                    SummaryBox(
                        label: "✓ アクションアイテム",
                        content: {
                            if actionItems.isEmpty {
                                Text("アクションアイテムはありません。")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Color.echoTextSecondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach($actionItems) { $item in
                                        Toggle(isOn: $item.isCompleted) {
                                            Text(item.text)
                                                .font(.system(size: 12.5))
                                                .foregroundStyle(Color.echoTextPrimary)
                                        }
                                        .toggleStyle(.checkbox)
                                        .onChange(of: item.isCompleted) { _, isCompleted in
                                            appState.updateActionItem(
                                                meetingID: meeting.id,
                                                itemID: item.id,
                                                isCompleted: isCompleted
                                            )
                                        }
                                    }
                                }
                                .padding(.top, 6)
                            }
                        }
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        if meeting.transcriptLines.isEmpty {
                            Text("文字起こしデータがありません。")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.echoTextSecondary)
                        } else {
                            ForEach(meeting.transcriptLines) { line in
                                TranscriptLineView(line: line)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Markdownで保存") {
                appState.exportMeetingToMarkdown(meeting: meeting)
            }
            .buttonStyle(EchoSecondaryButtonStyle())

            Button("Notionへ送る") {
                Task { await appState.exportToNotion(meeting: meeting) }
            }
            .buttonStyle(EchoSecondaryButtonStyle())
            .disabled(!appState.settingsStore.hasNotionConfiguration)

            Button("全文を見る") {
                appState.selectedTab = .transcript
            }
            .buttonStyle(EchoPrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { EchoDivider() }
    }
}

private struct SummaryBox<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color.echoAccent)
                .tracking(0.66)
                .textCase(.uppercase)

            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color.echoAccent.opacity(0.06),
                    Color.echoAccentTeal.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.echoAccent.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct EchoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.echoTextPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.echoBgPanel)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.echoBorder, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct EchoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.echoAccent)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
