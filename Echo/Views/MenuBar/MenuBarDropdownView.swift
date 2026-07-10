import SwiftUI

struct MenuBarDropdownView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var panelCoordinator: PanelCoordinator

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if appState.isRecording {
                        RecordingDot()
                        Text("文字起こし中 — \(appState.currentMeetingTitle) (\(appState.recordingDuration))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.echoTextPrimary)
                    } else {
                        Image(systemName: "mic")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.echoTextSecondary)
                        Text("待機中")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.echoTextPrimary)
                    }
                }

                Text(appState.detectedMeeting)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.echoTextSecondary)

                if let bannerMessage = appState.bannerMessage {
                    Text(bannerMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if appState.isRecording, appState.transcriptionService.isCapturingSystemAudio {
                    Text("話者A＝自分（マイク）／話者B＝相手（会議音声）")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.echoTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !appState.isRecording {
                    if appState.transcriptionService.isCapturingSystemAudio {
                        Text("話者A＝自分（マイク）／話者B＝相手（会議音声）")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.echoTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if appState.settingsStore.captureSystemAudio {
                        Text("会議音声の取得には画面収録の権限とブラウザを前面にしてください")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.echoTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { EchoDivider() }

            if appState.isRecording {
                MenuBarItem(
                    title: "停止する",
                    shortcut: "⌘⇧S",
                    isAccent: true
                ) {
                    Task { await appState.stopRecording() }
                }

                EchoDivider().padding(.horizontal, 0)
            } else {
                MenuBarItem(title: "文字起こしを開始", shortcut: "⌘⇧S", isAccent: true) {
                    Task {
                        appState.isFloatingPanelVisible = true
                        panelCoordinator.syncFloatingPanel(appState: appState)
                        await appState.toggleRecording()
                        panelCoordinator.syncFloatingPanel(appState: appState)
                    }
                }

                EchoDivider().padding(.horizontal, 0)
            }

            MenuBarItem(title: appState.isFloatingPanelVisible ? "フローティングパネルを隠す" : "フローティングパネルを表示") {
                appState.toggleFloatingPanel()
                panelCoordinator.syncFloatingPanel(appState: appState)
            }

            MenuBarItem(title: "履歴を開く", shortcut: "⌘O") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "history")
            }

            EchoDivider()

            MenuBarItem(title: "環境設定…", shortcut: "⌘,") {
                appState.isSettingsPresented = true
                openWindow(id: "settings")
            }
        }
        .frame(width: 260)
        .background {
            TranslucentPanelBackground()
        }
        .overlay {
            RoundedRectangle(cornerRadius: EchoRadius.window, style: .continuous)
                .stroke(Color.echoBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: EchoRadius.window, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 20)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .onReceive(NotificationCenter.default.publisher(for: .echoOpenSettings)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
    }
}

private struct MenuBarItem: View {
    let title: String
    var shortcut: String?
    var isAccent = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: isAccent ? .semibold : .regular))
                    .foregroundStyle(isAccent ? Color.echoAccent : Color.echoTextPrimary)

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.echoTextTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isHovered ? Color.black.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct MenuBarLabelView: View {
    @ObservedObject var iconController: MenuBarIconController

    var body: some View {
        HStack(spacing: 6) {
            WaveformIcon(
                animated: iconController.isRecording,
                externalTime: iconController.isRecording ? iconController.animationTime : 0,
                targetFPS: 12
            )
            .opacity(iconController.isRecording ? 1 : 0.55)

            Text("Echo")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.93))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
