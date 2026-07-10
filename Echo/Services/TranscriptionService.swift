import AVFoundation
import Foundation
import Speech

final class TranscriptionService: ObservableObject {
    @Published private(set) var liveLines: [TranscriptLine] = []
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var currentMeetingTitle = "会議"
    @Published private(set) var detectedSource: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isCapturingSystemAudio = false

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var micRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var systemRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var micRecognitionTask: SFSpeechRecognitionTask?
    private var systemRecognitionTask: SFSpeechRecognitionTask?
    private let systemAudioCapture = SystemAudioCaptureService()
    private var timer: Timer?
    private var startedAt = Date()
    private var partialLineIDs: [Speaker: UUID] = [:]
    private var lastFinalTimestamps: [Speaker: Date] = [.a: .distantPast, .b: .distantPast]
    private var usesDualChannel = false
    private var micOnlySpeaker: Speaker = .a

    var formattedDuration: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func permissionStatus() -> (speech: Bool, microphone: Bool) {
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        return (speech, mic)
    }

    func configure(localeIdentifier: String) {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    func requestPermissions() async -> (speech: Bool, microphone: Bool) {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }

        return (speechGranted, micGranted)
    }

    @MainActor
    func start(
        title: String,
        source: String?,
        captureSystemAudio: Bool,
        browserBundleID: String?
    ) async throws {
        guard !isRecording else { return }

        let permissions = Self.permissionStatus()
        guard permissions.microphone, permissions.speech else {
            throw TranscriptionError.permissionDenied
        }

        guard let speechRecognizer else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard speechRecognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        lastErrorMessage = nil
        currentMeetingTitle = title
        detectedSource = source
        liveLines = []
        elapsedSeconds = 0
        startedAt = Date()
        partialLineIDs = [:]
        lastFinalTimestamps = [.a: .distantPast, .b: .distantPast]
        usesDualChannel = false
        micOnlySpeaker = .a
        isCapturingSystemAudio = false

        let engine = AVAudioEngine()
        audioEngine = engine

        let micRequest = SFSpeechAudioBufferRecognitionRequest()
        micRequest.shouldReportPartialResults = true
        micRequest.requiresOnDeviceRecognition = false
        micRecognitionRequest = micRequest

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw TranscriptionError.audioInputUnavailable
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            micRequest.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanupAfterFailedStart()
            throw TranscriptionError.audioInputUnavailable
        }

        micRecognitionTask = speechRecognizer.recognitionTask(with: micRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(result, error: error, speaker: .a)
            }
        }

        if captureSystemAudio {
            do {
                let systemRequest = SFSpeechAudioBufferRecognitionRequest()
                systemRequest.shouldReportPartialResults = true
                systemRequest.requiresOnDeviceRecognition = false
                systemRecognitionRequest = systemRequest

                systemRecognitionTask = speechRecognizer.recognitionTask(with: systemRequest) { [weak self] result, error in
                    DispatchQueue.main.async {
                        self?.handleRecognitionResult(result, error: error, speaker: .b)
                    }
                }

                try await systemAudioCapture.start(preferredBundleID: browserBundleID) { [weak self] buffer in
                    self?.systemRecognitionRequest?.append(buffer)
                }

                usesDualChannel = true
                isCapturingSystemAudio = true
            } catch {
                systemRecognitionTask?.cancel()
                systemRecognitionRequest = nil
                systemRecognitionTask = nil
                lastErrorMessage = "\(error.localizedDescription)（マイクのみで続行します）"
            }
        }

        isRecording = true
        startTimer()
    }

    @MainActor
    func stop() -> StoredMeeting {
        timer?.invalidate()
        timer = nil
        isRecording = false
        isCapturingSystemAudio = false

        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        micRecognitionRequest?.endAudio()
        systemRecognitionRequest?.endAudio()
        micRecognitionTask?.cancel()
        systemRecognitionTask?.cancel()
        micRecognitionRequest = nil
        systemRecognitionRequest = nil
        micRecognitionTask = nil
        systemRecognitionTask = nil

        Task {
            await systemAudioCapture.stop()
        }

        finalizePartialLines()

        let endDate = Date()
        let storedLines = liveLines.map {
            StoredTranscriptLine(
                id: $0.id,
                speakerRaw: $0.speaker.rawValue,
                text: $0.text,
                isPartial: $0.isDimmed
            )
        }

        return StoredMeeting(
            title: currentMeetingTitle,
            startedAt: startedAt,
            endedAt: endDate,
            detectedSource: detectedSource,
            aiSummary: "",
            transcriptLines: storedLines,
            actionItems: []
        )
    }

    private func cleanupAfterFailedStart() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        micRecognitionRequest = nil
        micRecognitionTask?.cancel()
        micRecognitionTask = nil
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.elapsedSeconds += 1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handleRecognitionResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?,
        speaker: Speaker
    ) {
        if let error {
            let nsError = error as NSError
            if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 1110 {
                lastErrorMessage = error.localizedDescription
                print("Echo recognition error (\(speaker.label)): \(error)")
            }
        }

        guard let result else { return }

        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if result.isFinal {
            appendFinalLine(text, speaker: speaker)
        } else {
            updatePartialLine(text, speaker: speaker)
        }
    }

    private func appendFinalLine(_ text: String, speaker: Speaker) {
        finalizePartialLine(for: speaker)

        let resolved: Speaker
        if usesDualChannel {
            resolved = speaker
        } else {
            if Date().timeIntervalSince(lastFinalTimestamps[.a, default: .distantPast]) > 2.5 {
                micOnlySpeaker.toggle()
            }
            lastFinalTimestamps[.a] = Date()
            resolved = micOnlySpeaker
        }

        if usesDualChannel {
            lastFinalTimestamps[speaker] = Date()
        }

        let line = TranscriptLine(speaker: resolved, text: text, isDimmed: false)
        liveLines.append(line)
        partialLineIDs[speaker] = nil
        sortLiveLines()
        trimLiveLines()
    }

    private func resolvedSpeaker(for channelSpeaker: Speaker) -> Speaker {
        if usesDualChannel {
            return channelSpeaker
        }
        return micOnlySpeaker
    }

    private func updatePartialLine(_ text: String, speaker: Speaker) {
        let resolved = resolvedSpeaker(for: speaker)

        if let partialID = partialLineIDs[speaker],
           let index = liveLines.firstIndex(where: { $0.id == partialID }) {
            liveLines[index] = TranscriptLine(
                id: partialID,
                speaker: resolved,
                text: text,
                isDimmed: true
            )
        } else {
            let id = UUID()
            partialLineIDs[speaker] = id
            liveLines.append(TranscriptLine(id: id, speaker: resolved, text: text, isDimmed: true))
            sortLiveLines()
            trimLiveLines()
        }
    }

    private func finalizePartialLine(for speaker: Speaker) {
        guard let partialID = partialLineIDs[speaker],
              let index = liveLines.firstIndex(where: { $0.id == partialID }) else { return }
        let line = liveLines[index]
        liveLines[index] = TranscriptLine(id: line.id, speaker: line.speaker, text: line.text, isDimmed: false)
        partialLineIDs[speaker] = nil
    }

    private func finalizePartialLines() {
        finalizePartialLine(for: .a)
        finalizePartialLine(for: .b)
    }

    private func sortLiveLines() {
        // 話者ごとの確定順を保ちつつ、partial は末尾付近に維持
        let finals = liveLines.filter { !$0.isDimmed }
        let partials = liveLines.filter(\.isDimmed)
        liveLines = finals + partials
    }

    private func trimLiveLines() {
        if liveLines.count > 40 {
            liveLines.removeFirst(liveLines.count - 40)
        }
    }
}

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "音声認識エンジンが利用できません。システム設定で音声認識を有効にしてください。"
        case .permissionDenied:
            return "マイクまたは音声認識の権限が必要です。"
        case .audioInputUnavailable:
            return "マイク入力を取得できません。マイクの接続と権限を確認してください。"
        }
    }
}
