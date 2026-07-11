import AVFoundation
import Foundation
import SpeakerKit
import Speech
import WhisperKit

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
    private var usesDualChannel = false
    private var micOnlySpeakerIndex = 0
    private var currentRemoteSpeakerIndex = 0
    private var lastMicOnlyFinalAt = Date.distantPast
    private var lastSystemChannelFinalAt = Date.distantPast
    private let speakerPauseThreshold: TimeInterval = 2.5
    private var recordingSessionDirectory: URL?
    private var micRecorder: AudioRecordingWriter?
    private var systemRecorder: AudioRecordingWriter?

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
        async let speech = PermissionHelper.requestSpeechIfNeeded()
        async let microphone = PermissionHelper.requestMicrophoneIfNeeded()
        return await (speech: speech, microphone: microphone)
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
        usesDualChannel = false
        micOnlySpeakerIndex = 0
        currentRemoteSpeakerIndex = 0
        lastMicOnlyFinalAt = .distantPast
        lastSystemChannelFinalAt = .distantPast
        isCapturingSystemAudio = false
        recordingSessionDirectory = try? RecordingFileStore.makeSessionDirectory()
        micRecorder = nil
        systemRecorder = nil

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

        if let recordingSessionDirectory {
            let micURL = recordingSessionDirectory.appendingPathComponent("mic.wav")
            micRecorder = AudioRecordingWriter(url: micURL, format: recordingFormat)
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            micRequest.append(buffer)
            self?.micRecorder?.append(buffer)
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
                    self?.appendSystemAudioBuffer(buffer)
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
    func stop() async -> RecordingStopResult {
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

        await systemAudioCapture.stop()
        await micRecorder?.finish()
        await systemRecorder?.finish()

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

        let meeting = StoredMeeting(
            title: currentMeetingTitle,
            startedAt: startedAt,
            endedAt: endDate,
            detectedSource: detectedSource,
            aiSummary: "",
            transcriptLines: storedLines,
            actionItems: []
        )

        let micURL = micRecorder?.fileURL
        let systemURL = systemRecorder?.fileURL
        micRecorder = nil
        systemRecorder = nil

        return RecordingStopResult(
            meeting: meeting,
            sessionDirectory: recordingSessionDirectory,
            micAudioURL: micURL,
            systemAudioURL: systemURL,
            usesDualChannel: usesDualChannel
        )
    }

    private func appendSystemAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        if systemRecorder == nil,
           let recordingSessionDirectory {
            let format = buffer.format
            let systemURL = recordingSessionDirectory.appendingPathComponent("system.wav")
            systemRecorder = AudioRecordingWriter(url: systemURL, format: format)
        }
        systemRecorder?.append(buffer)
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

        let resolved = resolveSpeaker(for: speaker, isFinal: true)
        let line = TranscriptLine(speaker: resolved, text: text, isDimmed: false)
        liveLines.append(line)
        partialLineIDs[speaker] = nil
        sortLiveLines()
        trimLiveLines()
    }

    private func resolveSpeaker(for channelSpeaker: Speaker, isFinal: Bool) -> Speaker {
        if usesDualChannel {
            if channelSpeaker == .a {
                return .a
            }

            if isFinal {
                let now = Date()
                if lastSystemChannelFinalAt != .distantPast,
                   now.timeIntervalSince(lastSystemChannelFinalAt) > speakerPauseThreshold {
                    currentRemoteSpeakerIndex = min(
                        currentRemoteSpeakerIndex + 1,
                        Speaker.remoteOrder.count - 1
                    )
                }
                lastSystemChannelFinalAt = now
            }

            return Speaker.remoteSpeaker(at: currentRemoteSpeakerIndex)
        }

        if isFinal {
            let now = Date()
            if lastMicOnlyFinalAt != .distantPast,
               now.timeIntervalSince(lastMicOnlyFinalAt) > speakerPauseThreshold {
                micOnlySpeakerIndex = min(micOnlySpeakerIndex + 1, Speaker.allCases.count - 1)
            }
            lastMicOnlyFinalAt = now
        }

        return Speaker.allCases[micOnlySpeakerIndex]
    }

    private func resolvedSpeaker(for channelSpeaker: Speaker) -> Speaker {
        resolveSpeaker(for: channelSpeaker, isFinal: false)
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

// MARK: - Audio Recording

/// 録音中の PCM バッファを WAV ファイルへ書き込む。
final class AudioRecordingWriter {
    let fileURL: URL

    private let queue = DispatchQueue(label: "echo.audio-recording-writer")
    private var audioFile: AVAudioFile?

    init?(url: URL, format: AVAudioFormat) {
        fileURL = url
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            print("Echo: failed to create audio file at \(url.path): \(error)")
            return nil
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self, let audioFile else { return }
            do {
                try audioFile.write(from: buffer)
            } catch {
                print("Echo: audio write failed: \(error)")
            }
        }
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.audioFile = nil
                continuation.resume()
            }
        }
    }
}

enum RecordingFileStore {
    static func makeSessionDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-recordings", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func removeSession(at directory: URL?) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

struct RecordingStopResult {
    let meeting: StoredMeeting
    let sessionDirectory: URL?
    let micAudioURL: URL?
    let systemAudioURL: URL?
    let usesDualChannel: Bool
}

// MARK: - Post-Recording Diarization

private struct TimedTranscriptLine {
    let speaker: Speaker
    let text: String
    let startTime: TimeInterval
}

struct PostRecordingDiarizationService {
    enum DiarizationError: LocalizedError {
        case noAudio
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .noAudio:
                return "話者判別用の音声ファイルがありません。"
            case .emptyResult:
                return "話者判別の結果が空でした。"
            }
        }
    }

    func refineTranscript(
        micAudioURL: URL?,
        systemAudioURL: URL?,
        usesDualChannel: Bool,
        fallbackLines: [TranscriptLine]
    ) async throws -> [TranscriptLine] {
        let whisperKit = try await WhisperKit(WhisperKitConfig(model: "base"))
        let speakerKit = try await SpeakerKit()

        var timedLines: [TimedTranscriptLine] = []

        if usesDualChannel, let systemAudioURL {
            if let micAudioURL {
                let micLines = try await transcribeMicChannel(
                    url: micAudioURL,
                    whisperKit: whisperKit
                )
                timedLines.append(contentsOf: micLines)
            }
            let remoteLines = try await transcribeAndDiarizeRemoteChannel(
                url: systemAudioURL,
                whisperKit: whisperKit,
                speakerKit: speakerKit
            )
            timedLines.append(contentsOf: remoteLines)
        } else if let micAudioURL {
            timedLines = try await transcribeAndDiarizeSingleChannel(
                url: micAudioURL,
                whisperKit: whisperKit,
                speakerKit: speakerKit
            )
        } else {
            throw DiarizationError.noAudio
        }

        let refined = timedLines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startTime < $1.startTime }
            .map { TranscriptLine(speaker: $0.speaker, text: $0.text, isDimmed: false) }

        if refined.isEmpty {
            if fallbackLines.isEmpty {
                throw DiarizationError.emptyResult
            }
            return fallbackLines
        }

        return refined
    }

    private func transcribeMicChannel(
        url: URL,
        whisperKit: WhisperKit
    ) async throws -> [TimedTranscriptLine] {
        let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        guard !audioArray.isEmpty else { return [] }

        let transcription = try await whisperKit.transcribe(audioArray: audioArray)
        return flattenTranscription(transcription).map {
            TimedTranscriptLine(speaker: .a, text: $0.text, startTime: $0.startTime)
        }
    }

    private func transcribeAndDiarizeRemoteChannel(
        url: URL,
        whisperKit: WhisperKit,
        speakerKit: SpeakerKit
    ) async throws -> [TimedTranscriptLine] {
        let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        guard !audioArray.isEmpty else { return [] }

        let transcription = try await whisperKit.transcribe(audioArray: audioArray)
        let diarization = try await speakerKit.diarize(audioArray: audioArray)
        let speakerSegments = diarization.addSpeakerInfo(to: transcription)

        return mapSpeakerSegments(speakerSegments, remoteChannel: true)
    }

    private func transcribeAndDiarizeSingleChannel(
        url: URL,
        whisperKit: WhisperKit,
        speakerKit: SpeakerKit
    ) async throws -> [TimedTranscriptLine] {
        let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        guard !audioArray.isEmpty else { return [] }

        let transcription = try await whisperKit.transcribe(audioArray: audioArray)
        let diarization = try await speakerKit.diarize(audioArray: audioArray)
        let speakerSegments = diarization.addSpeakerInfo(to: transcription)

        return mapSpeakerSegments(speakerSegments, remoteChannel: false)
    }

    private struct FlatSegment {
        let text: String
        let startTime: TimeInterval
    }

    private func flattenTranscription(_ transcription: [TranscriptionResult]) -> [FlatSegment] {
        transcription.flatMap { result in
            result.segments.map { segment in
                FlatSegment(text: segment.text, startTime: TimeInterval(segment.start))
            }
        }
    }

    private func mapSpeakerSegments(
        _ speakerSegments: [[SpeakerSegment]],
        remoteChannel: Bool
    ) -> [TimedTranscriptLine] {
        var clusterOrder: [Int: Int] = [:]
        var nextClusterIndex = 0
        var lines: [TimedTranscriptLine] = []

        for group in speakerSegments {
            for segment in group {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                let clusterID = segment.speaker.speakerId ?? nextClusterIndex
                if clusterOrder[clusterID] == nil {
                    clusterOrder[clusterID] = nextClusterIndex
                    nextClusterIndex += 1
                }

                let mappedIndex = clusterOrder[clusterID] ?? 0
                let speaker = mapClusterIndex(mappedIndex, remoteChannel: remoteChannel)
                lines.append(
                    TimedTranscriptLine(
                        speaker: speaker,
                        text: text,
                        startTime: TimeInterval(segment.startTime)
                    )
                )
            }
        }

        return lines
    }

    private func mapClusterIndex(_ index: Int, remoteChannel: Bool) -> Speaker {
        if remoteChannel {
            return Speaker.remoteSpeaker(at: index)
        }
        return Speaker.allCases[min(index, Speaker.allCases.count - 1)]
    }
}
