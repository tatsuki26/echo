import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var permissionStatus = PermissionHelper.status()

    var body: some View {
        Form {
            Section("録音・検知") {
                Toggle("会議検知時に自動で文字起こしを開始（Google Meet / Zoom）", isOn: $settingsStore.autoStartOnMeetDetection)

                Toggle("会議の相手の声も文字起こしする", isOn: $settingsStore.captureSystemAudio)

                Toggle("録音停止後にローカルAIで話者を判別する", isOn: $settingsStore.enablePostRecordingDiarization)

                Picker("認識言語", selection: $settingsStore.localeIdentifier) {
                    Text("日本語").tag("ja-JP")
                    Text("English (US)").tag("en-US")
                }
                .onChange(of: settingsStore.localeIdentifier) { _, newValue in
                    appState.transcriptionService.configure(localeIdentifier: newValue)
                }

                Text("話者A＝自分（マイク）。会議音声側は録音停止後に SpeakerKit（Pyannote）で話者B〜Hを判別します。初回のみモデルをダウンロードします（無料・端末内処理）。会議音声の取得には画面収録の権限が必要です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI（任意）") {
                SecureField("API Key", text: $settingsStore.openAIAPIKey)
                Text("設定すると AI 要約・アクションアイテム抽出の精度が向上します。未設定時はオフライン要約を使用します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notion 連携") {
                SecureField("Internal Integration Token", text: $settingsStore.notionToken)
                TextField("Database ID", text: $settingsStore.notionDatabaseID)
                TextField("タイトルプロパティ名", text: $settingsStore.notionTitleProperty)

                Text("Notion でインテグレーションを作成し、対象データベースに接続してください。タイトル列のプロパティ名は通常「Name」です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("権限") {
                PermissionStatusRow(title: "マイク", isGranted: permissionStatus.microphone)
                PermissionStatusRow(title: "音声認識", isGranted: permissionStatus.speech)
                PermissionStatusRow(title: "画面収録", isGranted: permissionStatus.screenRecording)
                PermissionStatusRow(title: "アクセシビリティ", isGranted: permissionStatus.accessibility)

                Text("初回のみダイアログが表示されます。一度許可すれば、次回以降は聞かれません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("画面収録を許可したあとは、Echo を一度終了して再起動してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Google Meet / Zoom の自動検知には、ブラウザまたは Zoom アプリを前面にしてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PermissionSettingsButton(title: "マイクの設定を開く", pane: .microphone)
                PermissionSettingsButton(title: "音声認識の設定を開く", pane: .speechRecognition)
                PermissionSettingsButton(title: "画面収録の設定を開く", pane: .screenRecording)
                PermissionSettingsButton(title: "アクセシビリティの設定を開く", pane: .accessibility)
                PermissionSettingsButton(title: "自動化の設定を開く", pane: .automation)

                Button("マイク・音声認識の許可をリクエスト") {
                    Task {
                        _ = await appState.transcriptionService.requestPermissions()
                        refreshPermissionStatus()
                    }
                }

                Button("画面収録の許可をリクエスト") {
                    SystemAudioCaptureService.requestScreenRecordingPermission()
                    refreshPermissionStatus()
                }

                Button("アクセシビリティの許可をリクエスト") {
                    PermissionHelper.promptAccessibilityIfNeeded()
                    refreshPermissionStatus()
                }
            }

            Section("アプリ情報") {
                LabeledContent("バージョン") {
                    Text(Bundle.main.echoVersionString)
                }
                LabeledContent("ビルド") {
                    Text(Bundle.main.echoBuildString)
                }
                Text("Echo はメニューバー常駐の会議文字起こしアプリです。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("保存") {
                    settingsStore.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 680)
        .navigationTitle("環境設定")
        .onAppear {
            refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatusDebounced()
        }
    }

    private func refreshPermissionStatus() {
        permissionStatus = PermissionHelper.status()
    }

    private func refreshPermissionStatusDebounced() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            permissionStatus = PermissionHelper.status()
        }
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let isGranted: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(isGranted ? "許可済み" : "未許可")
                .foregroundStyle(isGranted ? Color.green : Color.orange)
                .font(.caption.weight(.semibold))
        }
    }
}

private struct PermissionSettingsButton: View {
    let title: String
    let pane: PermissionHelper.Pane

    var body: some View {
        Button(title) {
            PermissionHelper.openSettings(pane)
        }
    }
}
