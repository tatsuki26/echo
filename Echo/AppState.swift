import AppKit
import AVFoundation
import Combine
import Foundation
import Speech
import SwiftUI

final class AppState: ObservableObject {
    @Published var searchQuery = ""
    @Published var selectedMeetingID: UUID?
    @Published var mainWindowScreen: MainWindowScreen = .home
    @Published var selectedTab: MeetingDetailTab = .summary
    @Published var isFloatingPanelVisible = false
    @Published var isSettingsPresented = false
    @Published var bannerMessage: String?
    @Published var isProcessing = false

    let transcriptionService: TranscriptionService
    let meetingStore: MeetingStore
    let meetingDetector: MeetingDetector
    let settingsStore: SettingsStore
    let summaryService = SummaryService()
    let notionService = NotionService()
    let shortcutManager = GlobalShortcutManager()
    let postRecordingDiarizationService = PostRecordingDiarizationService()

    let menuBarIconController: MenuBarIconController

    private var lastAutoStartedMeetingTitle: String?
    private var lastBecameActiveAt = Date.distantPast
    private let launchedAt = Date()
    private var cancellables = Set<AnyCancellable>()

    init(
        transcriptionService: TranscriptionService,
        meetingStore: MeetingStore,
        meetingDetector: MeetingDetector,
        settingsStore: SettingsStore,
        menuBarIconController: MenuBarIconController
    ) {
        self.transcriptionService = transcriptionService
        self.meetingStore = meetingStore
        self.meetingDetector = meetingDetector
        self.settingsStore = settingsStore
        self.menuBarIconController = menuBarIconController

        transcriptionService.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak menuBarIconController] isRecording in
                menuBarIconController?.setRecording(isRecording)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.lastBecameActiveAt = Date()
            }
            .store(in: &cancellables)
    }

    var isRecording: Bool { transcriptionService.isRecording }
    var recordingDuration: String { transcriptionService.formattedDuration }
    var currentMeetingTitle: String { transcriptionService.currentMeetingTitle }
    var liveTranscriptLines: [TranscriptLine] { transcriptionService.liveLines }
    var detectedMeeting: String { meetingDetector.statusMessage }
    var meetings: [Meeting] { meetingStore.meetings }

    var filteredMeetings: [Meeting] {
        guard !searchQuery.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery)
                || $0.preview.localizedCaseInsensitiveContains(searchQuery)
                || $0.aiSummary.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var selectedMeeting: Meeting? {
        guard let selectedMeetingID else { return nil }
        return meetingStore.meeting(id: selectedMeetingID)
    }

    func bootstrap() async {
        UserNotificationService.requestAuthorizationIfNeeded()
        transcriptionService.configure(localeIdentifier: settingsStore.localeIdentifier)
        registerShortcuts()
        meetingStore.seedSampleDataIfNeeded()

        if let first = meetingStore.meetings.first, selectedMeetingID == nil {
            selectedMeetingID = first.id
        }

        meetingDetector.setOnMeetingDetected { [weak self] meeting in
            self?.handleMeetDetection(meeting)
        }
        meetingDetector.startMonitoring()
    }

    func requestPermissionsIfNeeded() async -> Bool {
        let current = PermissionHelper.status()

        if current.microphone && current.speech {
            return true
        }

        let permissions = await transcriptionService.requestPermissions()

        if !permissions.microphone {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .denied || status == .restricted {
                presentPermissionIssue(
                    "マイクの権限が必要です。システム設定 → プライバシーとセキュリティ → マイク で Echo を許可してください。"
                )
                PermissionHelper.openSettings(.microphone)
            }
            return false
        }
        if !permissions.speech {
            let status = SFSpeechRecognizer.authorizationStatus()
            if status == .denied || status == .restricted {
                presentPermissionIssue(
                    "音声認識の権限が必要です。システム設定 → プライバシーとセキュリティ → 音声認識 で Echo を許可してください。"
                )
                PermissionHelper.openSettings(.speechRecognition)
            }
            return false
        }
        return true
    }

    func registerShortcuts() {
        shortcutManager.onToggleRecording = { [weak self] in
            Task { @MainActor in
                await self?.toggleRecording()
            }
        }
        shortcutManager.onOpenHistory = { [weak self] in
            self?.openHistoryWindow()
        }
        shortcutManager.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        shortcutManager.register()
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
            return
        }

        if let meeting = meetingDetector.detectedMeeting {
            await startRecording(title: meeting.title, source: meeting.source)
        } else {
            await startRecording(title: "会議", source: nil)
        }
    }

    func openHistoryWindow() {
        mainWindowScreen = .history
        NotificationCenter.default.post(name: .echoOpenHistory, object: nil)
    }

    func openHomeWindow() {
        mainWindowScreen = .home
        NotificationCenter.default.post(name: .echoOpenHistory, object: nil)
    }

    func showMainWindow() {
        NotificationCenter.default.post(name: .echoOpenHistory, object: nil)
    }

    func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .echoOpenSettings, object: nil)
    }

    func handleMeetDetection(_ meeting: DetectedMeetingInfo?) {
        guard settingsStore.autoStartOnMeetDetection,
              let meeting,
              !isRecording else { return }

        // 起動直後の自動録音開始を避ける
        guard Date().timeIntervalSince(launchedAt) > 45 else { return }

        // システム設定から戻った直後の自動録音開始を避ける
        guard Date().timeIntervalSince(lastBecameActiveAt) > 2.0 else { return }

        if lastAutoStartedMeetingTitle == meeting.title { return }

        Task {
            await startRecording(title: meeting.title, source: meeting.source)
        }
    }

    func startRecording(title: String, source: String?) async {
        guard !isRecording else { return }

        guard await requestPermissionsIfNeeded() else {
            lastAutoStartedMeetingTitle = nil
            return
        }

        transcriptionService.configure(localeIdentifier: settingsStore.localeIdentifier)

        do {
            try await transcriptionService.start(
                title: title,
                source: source,
                captureSystemAudio: settingsStore.captureSystemAudio,
                browserBundleID: meetingDetector.detectedMeeting?.browserBundleID
                    ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            )
            lastAutoStartedMeetingTitle = title
            NotificationCenter.default.post(name: .echoRecordingStateChanged, object: nil)

            let captureNote = transcriptionService.isCapturingSystemAudio
                ? "話者A＝自分（マイク）。会議音声は発言間隔から話者B以降を推定します。"
                : "マイクに向かって話してください。発言間隔から話者を推定します。"
            let message = "「\(title)」の文字起こしを開始しました。\(captureNote)"
            bannerMessage = message
            UserNotificationService.notify(title: "Echo", body: message)
        } catch {
            lastAutoStartedMeetingTitle = nil
            presentPermissionIssue(error.localizedDescription)
        }
    }

    private func presentPermissionIssue(_ message: String) {
        bannerMessage = message
        UserNotificationService.notify(title: "Echo — エラー", body: message)
    }

    func stopRecording() async {
        guard isRecording else { return }
        isProcessing = true
        defer { isProcessing = false }

        let recordingResult = await transcriptionService.stop()
        var stored = recordingResult.meeting

        var lines = stored.transcriptLines.map {
            TranscriptLine(
                id: $0.id,
                speaker: $0.speaker,
                text: $0.text,
                isDimmed: $0.isPartial
            )
        }

        var diarizationFailed = false

        if settingsStore.enablePostRecordingDiarization {
            bannerMessage = "AIで話者を判別しています…（初回はモデルのダウンロードがあります）"
            do {
                let refinedLines = try await postRecordingDiarizationService.refineTranscript(
                    micAudioURL: recordingResult.micAudioURL,
                    systemAudioURL: recordingResult.systemAudioURL,
                    usesDualChannel: recordingResult.usesDualChannel,
                    fallbackLines: lines
                )
                lines = refinedLines
                stored.transcriptLines = refinedLines.map {
                    StoredTranscriptLine(
                        id: $0.id,
                        speakerRaw: $0.speaker.rawValue,
                        text: $0.text,
                        isPartial: false
                    )
                }
            } catch {
                diarizationFailed = true
                print("Echo: post-recording diarization failed: \(error)")
            }
        }

        RecordingFileStore.removeSession(at: recordingResult.sessionDirectory)

        let generated = await summaryService.generateSummary(
            from: lines,
            apiKey: settingsStore.openAIAPIKey
        )

        stored.aiSummary = generated.summary
        stored.actionItems = generated.actionItems.map {
            StoredActionItem(id: $0.id, text: $0.text, isCompleted: $0.isCompleted, meeting: stored)
        }

        meetingStore.saveMeeting(stored)
        selectedMeetingID = stored.id
        mainWindowScreen = .detail
        selectedTab = .summary
        lastAutoStartedMeetingTitle = nil
        bannerMessage = diarizationFailed
            ? "会議を保存しました（話者判別はリアルタイム結果を使用）。"
            : settingsStore.enablePostRecordingDiarization
                ? "会議を保存し、AIで話者を判別して要約を生成しました。"
                : "会議を保存し、要約を生成しました。"
        NotificationCenter.default.post(name: .echoOpenHistory, object: nil)
    }

    func toggleFloatingPanel() {
        isFloatingPanelVisible.toggle()
    }

    func updateActionItem(meetingID: UUID, itemID: UUID, isCompleted: Bool) {
        meetingStore.updateActionItem(meetingID: meetingID, itemID: itemID, isCompleted: isCompleted)
    }

    func deleteMeeting(id: UUID) {
        meetingStore.deleteMeeting(id: id)
        if selectedMeetingID == id {
            selectedMeetingID = meetingStore.meetings.first?.id
            mainWindowScreen = meetingStore.meetings.isEmpty ? .home : .history
        }
        bannerMessage = "会議を削除しました。"
    }

    func exportMeetingToMarkdown(meeting: Meeting) {
        Task { @MainActor in
            if let url = MeetingExportService.exportViaSavePanel(meeting: meeting) {
                bannerMessage = "Markdown を保存しました。"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    func exportToNotion(meeting: Meeting) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let configuration = NotionConfiguration(
                token: settingsStore.notionToken,
                databaseID: settingsStore.notionDatabaseID,
                titleProperty: settingsStore.notionTitleProperty
            )
            let url = try await notionService.exportMeeting(meeting, configuration: configuration)
            bannerMessage = "Notion に送信しました。"
            NSWorkspace.shared.open(url)
        } catch {
            bannerMessage = error.localizedDescription
        }
    }
}

enum MainWindowScreen: Equatable {
    case home
    case history
    case detail
}

enum MeetingDetailTab: String, CaseIterable {
    case summary = "要約"
    case transcript = "文字起こし全文"
}

extension Notification.Name {
    static let echoOpenHistory = Notification.Name("echoOpenHistory")
    static let echoOpenSettings = Notification.Name("echoOpenSettings")
    static let echoApplicationDidLaunch = Notification.Name("echoApplicationDidLaunch")
    static let echoRecordingStateChanged = Notification.Name("echoRecordingStateChanged")
}
