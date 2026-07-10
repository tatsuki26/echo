import AppKit
import Combine
import Foundation
import SwiftUI

final class AppState: ObservableObject {
    @Published var searchQuery = ""
    @Published var selectedMeetingID: UUID?
    @Published var isShowingDetail = false
    @Published var selectedTab: MeetingDetailTab = .summary
    @Published var isFloatingPanelVisible = true
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

    let menuBarIconController: MenuBarIconController

    private var lastAutoStartedMeetingTitle: String?
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

        transcriptionService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        meetingDetector.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        transcriptionService.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak menuBarIconController] isRecording in
                menuBarIconController?.setRecording(isRecording)
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
        let permissions = await transcriptionService.requestPermissions()
        if !permissions.microphone {
            presentPermissionIssue(
                "マイクの権限が必要です。システム設定 → プライバシーとセキュリティ → マイク で Echo を許可してください。"
            )
            PermissionHelper.openSettings(.microphone)
            return false
        }
        if !permissions.speech {
            presentPermissionIssue(
                "音声認識の権限が必要です。システム設定 → プライバシーとセキュリティ → 音声認識 で Echo を許可してください。"
            )
            PermissionHelper.openSettings(.speechRecognition)
            return false
        }
        return true
    }

    func registerShortcuts() {
        PermissionHelper.promptAccessibilityIfNeeded()

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
        NSApp.activate(ignoringOtherApps: true)
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
            isFloatingPanelVisible = true
            NotificationCenter.default.post(name: .echoRecordingStateChanged, object: nil)

            let captureNote = transcriptionService.isCapturingSystemAudio
                ? "マイク（話者A）と会議音声（話者B）を文字起こししています。"
                : "マイクに向かって話してください。"
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

        let stored = await MainActor.run {
            transcriptionService.stop()
        }
        let lines = stored.transcriptLines.map {
            TranscriptLine(
                id: $0.id,
                speaker: $0.speaker,
                text: $0.text,
                isDimmed: $0.isPartial
            )
        }

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
        isShowingDetail = true
        selectedTab = .summary
        lastAutoStartedMeetingTitle = nil
        bannerMessage = "会議を保存し、要約を生成しました。"
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
            isShowingDetail = false
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
