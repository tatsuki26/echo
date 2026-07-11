import SwiftUI

struct HomeView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var transcriptionService: TranscriptionService
    @EnvironmentObject private var meetingDetector: MeetingDetector
    @EnvironmentObject private var panelCoordinator: PanelCoordinator

    private var recentMeetings: [Meeting] {
        Array(appState.meetings.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                primaryActions
                recentMeetingsSection
                shortcutsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.echoBgPage)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if transcriptionService.isRecording {
                    RecordingDot()
                    Text("文字起こし中")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.echoTextPrimary)
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.echoTextSecondary)
                    Text("待機中")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.echoTextPrimary)
                }

                Spacer()

                if transcriptionService.isRecording {
                    Text(transcriptionService.formattedDuration)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.echoAccent)
                }
            }

            if transcriptionService.isRecording {
                Text(transcriptionService.currentMeetingTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.echoTextPrimary)

                Text("停止後にローカルAIで話者を判別します")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.echoTextTertiary)
            } else {
                Text(meetingDetector.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.echoTextSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.echoBgPanel)
        .clipShape(RoundedRectangle(cornerRadius: EchoRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EchoRadius.card, style: .continuous)
                .stroke(Color.echoBorder, lineWidth: 1)
        }
    }

    private var primaryActions: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if transcriptionService.isRecording {
                        await appState.stopRecording()
                    } else {
                        await appState.toggleRecording()
                    }
                }
            } label: {
                Label(
                    transcriptionService.isRecording ? "停止する" : "文字起こしを開始",
                    systemImage: transcriptionService.isRecording ? "stop.fill" : "mic.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(transcriptionService.isRecording ? Color.echoDanger : Color.echoAccent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                appState.mainWindowScreen = .history
            } label: {
                Label("履歴を見る", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.echoAccent)
            .background(Color.echoAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var recentMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近の会議")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.echoTextPrimary)

                Spacer()

                if !appState.meetings.isEmpty {
                    Button("すべて見る") {
                        appState.mainWindowScreen = .history
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.echoAccent)
                }
            }

            if recentMeetings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.echoTextTertiary)
                    Text("まだ会議がありません")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.echoTextSecondary)
                    Text("文字起こしを開始すると、ここに表示されます")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.echoTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color.echoBgPanel)
                .clipShape(RoundedRectangle(cornerRadius: EchoRadius.card, style: .continuous))
            } else {
                VStack(spacing: 2) {
                    ForEach(recentMeetings) { meeting in
                        MeetingRowView(
                            meeting: meeting,
                            isSelected: false,
                            highlightTerm: ""
                        )
                        .onTapGesture {
                            appState.selectedMeetingID = meeting.id
                            appState.mainWindowScreen = .detail
                        }
                    }
                }
            }
        }
    }

    private var shortcutsSection: some View {
        HStack(spacing: 10) {
            HomeShortcutButton(
                title: "フローティング",
                icon: appState.isFloatingPanelVisible ? "rectangle.on.rectangle" : "rectangle.on.rectangle.slash",
                action: {
                    appState.toggleFloatingPanel()
                    panelCoordinator.syncFloatingPanel(appState: appState)
                }
            )

            HomeShortcutButton(title: "環境設定", icon: "gearshape") {
                appState.isSettingsPresented = true
                openWindow(id: "settings")
            }
        }
    }
}

private struct HomeShortcutButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.echoTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isHovered ? Color.echoBgPanel : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.echoBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
