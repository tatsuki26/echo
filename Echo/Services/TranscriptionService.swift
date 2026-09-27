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
    /// マイク入力が途絶えている等、録音が正常に行えていない場合の警告
    @Published private(set) var inputWarning: String?

    /// 音声入力レベル（メニューバー・フローティングパネルの波形表示用）
    let levelMeter = AudioLevelMeter()

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private let micPipe = RecognitionRequestPipe()
    private let systemPipe = RecognitionRequestPipe()
    private var micRecognitionTask: SFSpeechRecognitionTask?
    private var systemRecognitionTask: SFSpeechRecognitionTask?
    private var recognitionGeneration: [Speaker: Int] = [:]
    private var lastRecognitionRestartAt: [Speaker: Date] = [:]
    private let systemAudioCapture = SystemAudioCaptureService()
    private var timer: Timer?
    private var startedAt = Date()
    private var partialLineIDs: [Speaker: UUID] = [:]
    /// 会議全体の確定済み文字起こし（liveLines は表示用に件数を制限している）
    private var fullTranscript: [TranscriptLine] = []
    private var usesDualChannel = false
    private var micOnlySpeakerIndex = 0
    private var currentRemoteSpeakerIndex = 0
    private var lastMicOnlyFinalAt = Date.distantPast
    private var lastSystemChannelFinalAt = Date.distantPast
    private let speakerPauseThreshold: TimeInterval = 2.5
    private let micStallThreshold: TimeInterval = 3
    private var lastEngineRestartAt = Date.distantPast
    private var engineConfigObserver: NSObjectProtocol?
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
        inputWarning = nil
        currentMeetingTitle = title
        detectedSource = source
        liveLines = []
        fullTranscript = []
        elapsedSeconds = 0
        startedAt = Date()
        partialLineIDs = [:]
        recognitionGeneration = [:]
        lastRecognitionRestartAt = [:]
        usesDualChannel = false
        micOnlySpeakerIndex = 0
        currentRemoteSpeakerIndex = 0
        lastMicOnlyFinalAt = .distantPast
        lastSystemChannelFinalAt = .distantPast
        lastEngineRestartAt = .distantPast
        isCapturingSystemAudio = false
        levelMeter.reset()
        recordingSessionDirectory = try? RecordingFileStore.makeSessionDirectory()
        micRecorder = nil
        systemRecorder = nil

        if let recordingSessionDirectory {
            micRecorder = AudioRecordingWriter(url: recordingSessionDirectory.appendingPathComponent("mic.wav"))
        }

        // 認識タスクはタップより先に用意しておく（最初の発話を取りこぼさないため）
        startRecognitionTask(for: .a)

        do {
            try startAudioEngine()
        } catch {
            cleanupAfterFailedStart()
            throw error
        }
        observeEngineConfigurationChanges()

        if captureSystemAudio {
            do {
                startRecognitionTask(for: .b)

                try await systemAudioCapture.start(preferredBundleID: browserBundleID) { [weak self] buffer in
                    guard let self else { return }
                    self.levelMeter.ingest(buffer, channel: .system)
                    self.systemPipe.append(buffer)
                    self.appendSystemAudioBuffer(buffer)
                }

                usesDualChannel = true
                isCapturingSystemAudio = true
            } catch {
                stopRecognitionTask(for: .b)
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
        inputWarning = nil

        if let engineConfigObserver {
            NotificationCenter.default.removeObserver(engineConfigObserver)
        }
        engineConfigObserver = nil

        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        stopRecognitionTask(for: .a)
        stopRecognitionTask(for: .b)

        await systemAudioCapture.stop()
        await micRecorder?.finish()
        await systemRecorder?.finish()
        levelMeter.reset()

        finalizePartialLines()

        let endDate = Date()
        let storedLines = fullTranscript.map {
            StoredTranscriptLine(
                id: $0.id,
                speakerRaw: $0.speaker.rawValue,
                text: $0.text,
                isPartial: false
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

    // MARK: - Audio Engine

    private func startAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw TranscriptionError.audioInputUnavailable
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.levelMeter.ingest(buffer, channel: .mic)
            self.micPipe.append(buffer)
            self.micRecorder?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw TranscriptionError.audioInputUnavailable
        }

        audioEngine = engine
        lastEngineRestartAt = Date()
    }

    /// AirPods の接続や会議アプリによるマイク設定変更でエンジンが停止するため、再構築する。
    private func observeEngineConfigurationChanges() {
        if let engineConfigObserver {
            NotificationCenter.default.removeObserver(engineConfigObserver)
        }
        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let engine = notification.object as? AVAudioEngine,
                  engine === self.audioEngine else { return }
            print("Echo: audio engine configuration changed, restarting input")
            self.restartAudioEngine()
        }
    }

    private func restartAudioEngine() {

        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        do {
            try startAudioEngine()
            // 入力フォーマットが変わった可能性があるため認識タスクも作り直す
            finalizePartialLine(for: .a)
            startRecognitionTask(for: .a)
        } catch {
            lastEngineRestartAt = Date()
            inputWarning = "マイク入力を再開できません。入力デバイスを確認してください。"
        }
    }

    /// 録音中に 1 秒ごとに呼ばれ、マイク入力が途絶えていないか確認する。
    private func checkInputHealth() {
        guard isRecording else { return }

        let snapshot = levelMeter.snapshot()
        let now = Date()
        let micStalled = now.timeIntervalSince(max(snapshot.lastMicBufferAt, lastEngineRestartAt)) > micStallThreshold

        if micStalled {
            inputWarning = "マイクの音声が届いていません。再接続しています…"
            if now.timeIntervalSince(lastEngineRestartAt) > micStallThreshold {
                restartAudioEngine()
            }
        } else if inputWarning != nil {
            inputWarning = nil
        }
    }

    // MARK: - Speech Recognition

    private func pipe(for channel: Speaker) -> RecognitionRequestPipe {
        channel == .a ? micPipe : systemPipe
    }

    /// SFSpeechRecognizer のタスクは約 1 分・無音・確定のいずれかで終了するため、
    /// 録音中はチャンネルごとに作り直し続ける。
    private func startRecognitionTask(for channel: Speaker) {
        guard let speechRecognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if speechRecognizer.supportsOnDeviceRecognition {
            // オンデバイス認識はサーバーの 1 分制限やネットワーク断の影響を受けない
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true

        let generation = (recognitionGeneration[channel] ?? 0) + 1
        recognitionGeneration[channel] = generation
        lastRecognitionRestartAt[channel] = Date()

        let previousRequest = pipe(for: channel).replace(with: request)
        previousRequest?.endAudio()

        let task = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(result, error: error, speaker: channel, generation: generation)
            }
        }

        if channel == .a {
            micRecognitionTask?.cancel()
            micRecognitionTask = task
        } else {
            systemRecognitionTask?.cancel()
            systemRecognitionTask = task
        }
    }

    private func stopRecognitionTask(for channel: Speaker) {
        recognitionGeneration[channel] = (recognitionGeneration[channel] ?? 0) + 1
        pipe(for: channel).replace(with: nil)?.endAudio()
        if channel == .a {
            micRecognitionTask?.cancel()
            micRecognitionTask = nil
        } else {
            systemRecognitionTask?.cancel()
            systemRecognitionTask = nil
        }
    }

    private func scheduleRecognitionRestart(for channel: Speaker) {
        guard audioEngine != nil else { return }

        // エラーが連続する場合に再起動が暴走しないよう最低間隔を空ける
        let elapsed = Date().timeIntervalSince(lastRecognitionRestartAt[channel] ?? .distantPast)
        let delay = max(0, 1.0 - elapsed)
        let generation = recognitionGeneration[channel] ?? 0

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.audioEngine != nil,
                  self.recognitionGeneration[channel] == generation else { return }
            self.startRecognitionTask(for: channel)
        }
    }

    private func appendSystemAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        if systemRecorder == nil,
           let recordingSessionDirectory {
            let systemURL = recordingSessionDirectory.appendingPathComponent("system.wav")
            systemRecorder = AudioRecordingWriter(url: systemURL)
        }
        systemRecorder?.append(buffer)
    }

    private func cleanupAfterFailedStart() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        stopRecognitionTask(for: .a)
        stopRecognitionTask(for: .b)
        levelMeter.reset()
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(self.startedAt))
                self.checkInputHealth()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handleRecognitionResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?,
        speaker: Speaker,
        generation: Int
    ) {
        // 作り直し前の古いタスクからのコールバックは無視する
        guard recognitionGeneration[speaker] == generation else { return }

        if let result {
            let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                if result.isFinal {
                    appendFinalLine(text, speaker: speaker)
                } else {
                    updatePartialLine(text, speaker: speaker)
                }
            }
        }

        if let error {
            let nsError = error as NSError
            // 1110 = 無音（No speech detected）, 216/301 = キャンセル。いずれも再起動で回復する
            let benign = nsError.domain == "kAFAssistantErrorDomain" && [1110, 216, 301].contains(nsError.code)
            if !benign {
                lastErrorMessage = error.localizedDescription
                print("Echo recognition error (\(speaker.label)): \(error)")
            }
            finalizePartialLine(for: speaker)
            scheduleRecognitionRestart(for: speaker)
        } else if result?.isFinal == true {
            scheduleRecognitionRestart(for: speaker)
        }
    }

    private func appendFinalLine(_ text: String, speaker: Speaker) {
        let resolved = resolveSpeaker(for: speaker, isFinal: true)

        if let partialID = partialLineIDs[speaker],
           let index = liveLines.firstIndex(where: { $0.id == partialID }) {
            // 途中結果の行を確定テキストで置き換える（重複行を作らない）
            let line = TranscriptLine(id: partialID, speaker: resolved, text: text, isDimmed: false)
            liveLines[index] = line
            fullTranscript.append(line)
        } else {
            let line = TranscriptLine(speaker: resolved, text: text, isDimmed: false)
            liveLines.append(line)
            fullTranscript.append(line)
        }
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

    /// 確定結果が得られなかった途中結果を、そのまま確定行として残す。
    private func finalizePartialLine(for speaker: Speaker) {
        guard let partialID = partialLineIDs[speaker] else { return }
        partialLineIDs[speaker] = nil
        guard let index = liveLines.firstIndex(where: { $0.id == partialID }) else { return }
        let line = liveLines[index]
        let finalized = TranscriptLine(id: line.id, speaker: line.speaker, text: line.text, isDimmed: false)
        liveLines[index] = finalized
        fullTranscript.append(finalized)
        sortLiveLines()
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
        // 表示用のみ制限する。保存は fullTranscript から行う
        if liveLines.count > 40 {
            liveLines.removeFirst(liveLines.count - 40)
        }
    }
}

/// オーディオスレッドから現在の認識リクエストへバッファを渡すためのスレッドセーフな入れ物。
final class RecognitionRequestPipe {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = request
        lock.unlock()
        request?.append(buffer)
    }

    /// 新しいリクエストに差し替え、以前のリクエストを返す。
    @discardableResult
    func replace(with newRequest: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let previous = request
        request = newRequest
        return previous
    }
}

// MARK: - Audio Level

/// マイク／システム音声の入力レベルを保持する。オーディオスレッドから書き込み、UI からポーリングで読む。
final class AudioLevelMeter {
    enum Channel {
        case mic
        case system
    }

    struct Snapshot {
        var micLevel: Float = 0
        var systemLevel: Float = 0
        var lastMicBufferAt = Date.distantPast
        var lastSystemBufferAt = Date.distantPast

        /// 波形表示用の合成レベル（0...1）
        var combinedLevel: Float { max(micLevel, systemLevel) }
    }

    private let lock = NSLock()
    private var state = Snapshot()
    /// これ以上バッファが来なければレベルを 0 とみなす
    private let staleInterval: TimeInterval = 0.5

    func reset() {
        lock.lock()
        state = Snapshot()
        lock.unlock()
    }

    func ingest(_ buffer: AVAudioPCMBuffer, channel: Channel) {
        let level = Self.normalizedLevel(of: buffer)
        let now = Date()

        lock.lock()
        switch channel {
        case .mic:
            state.micLevel = Self.smooth(previous: state.micLevel, next: level)
            state.lastMicBufferAt = now
        case .system:
            state.systemLevel = Self.smooth(previous: state.systemLevel, next: level)
            state.lastSystemBufferAt = now
        }
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        var snapshot = state
        lock.unlock()

        let now = Date()
        if now.timeIntervalSince(snapshot.lastMicBufferAt) > staleInterval {
            snapshot.micLevel = 0
        }
        if now.timeIntervalSince(snapshot.lastSystemBufferAt) > staleInterval {
            snapshot.systemLevel = 0
        }
        return snapshot
    }

    /// 立ち上がりは速く、減衰はゆっくり
    private static func smooth(previous: Float, next: Float) -> Float {
        next > previous ? next : previous * 0.6 + next * 0.4
    }

    /// RMS を dB に変換し、-55dB〜-10dB を 0〜1 に正規化する。
    private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        var sampleCount = 0

        if let floatData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            let stride = buffer.stride
            for channel in 0..<channelCount {
                let samples = floatData[channel]
                for frame in 0..<frameLength {
                    let sample = samples[frame * stride]
                    sum += sample * sample
                }
                sampleCount += frameLength
            }
        } else if let int16Data = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            let stride = buffer.stride
            for channel in 0..<channelCount {
                let samples = int16Data[channel]
                for frame in 0..<frameLength {
                    let sample = Float(samples[frame * stride]) / Float(Int16.max)
                    sum += sample * sample
                }
                sampleCount += frameLength
            }
        } else {
            return 0
        }

        guard sampleCount > 0 else { return 0 }
        let rms = sqrt(sum / Float(sampleCount))
        let decibels = 20 * log10(max(rms, 1e-7))
        let minDb: Float = -55
        let maxDb: Float = -10
        return min(1, max(0, (decibels - minDb) / (maxDb - minDb)))
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
/// 入力フォーマット（デバイス切替でサンプルレートやチャンネル数が変わる）に関わらず、
/// 16kHz モノラルに変換して 1 つのファイルに書き込む。
final class AudioRecordingWriter {
    let fileURL: URL

    private let queue = DispatchQueue(label: "echo.audio-recording-writer")
    private var audioFile: AVAudioFile?
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    init?(url: URL) {
        fileURL = url
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else { return nil }
        self.outputFormat = outputFormat

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            print("Echo: failed to create audio file at \(url.path): \(error)")
            return nil
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        // タップのバッファは再利用される可能性があるため、非同期書き込み前にコピーする
        guard let copy = buffer.echoCopy() else { return }
        queue.async { [weak self] in
            self?.write(copy)
        }
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.audioFile = nil
                self?.converter = nil
                continuation.resume()
            }
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile else { return }

        if converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            converterInputFormat = buffer.format
        }
        guard let converter else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, output.frameLength > 0 else {
            if let error {
                print("Echo: audio convert failed: \(error)")
            }
            return
        }

        do {
            try audioFile.write(from: output)
        } catch {
            print("Echo: audio write failed: \(error)")
        }
    }
}

extension AVAudioPCMBuffer {
    func echoCopy() -> AVAudioPCMBuffer? {
        guard frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength

        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(source, destination) {
            guard let srcData = src.mData, let dstData = dst.mData else { continue }
            memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
        }
        return copy
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
