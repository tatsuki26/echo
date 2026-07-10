import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

enum SystemAudioCaptureError: LocalizedError {
    case screenRecordingPermissionRequired
    case applicationNotFound
    case streamFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionRequired:
            return "画面収録の権限が必要です。システム設定で Echo を許可してください。"
        case .applicationNotFound:
            return "ブラウザまたは Zoom アプリが見つかりません。会議アプリを前面にしてください。"
        case .streamFailed(let message):
            return "システム音声の取得に失敗しました: \(message)"
        }
    }
}

/// Google Meet 等のブラウザアプリから相手の声（システム音声）を取得する。
final class SystemAudioCaptureService: NSObject, SCStreamOutput {
    static let captureBundleIDs = [
        "company.thebrowser.Browser",
        "com.google.Chrome",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "us.zoom.xos"
    ]

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "echo.system-audio", qos: .userInitiated)
    private var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?

    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    func start(
        preferredBundleID: String?,
        onAudioBuffer: @escaping (AVAudioPCMBuffer) -> Void
    ) async throws {
        guard Self.hasScreenRecordingPermission() else {
            Self.requestScreenRecordingPermission()
            throw SystemAudioCaptureError.screenRecordingPermissionRequired
        }

        self.onAudioBuffer = onAudioBuffer

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw SystemAudioCaptureError.streamFailed("ディスプレイが見つかりません")
        }

        let targetBundleID = resolveTargetBundleID(preferred: preferredBundleID, content: content)
        guard let bundleID = targetBundleID,
              let application = content.applications.first(where: { $0.bundleIdentifier == bundleID }) else {
            throw SystemAudioCaptureError.applicationNotFound
        }

        let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)

        do {
            try await stream.startCapture()
        } catch {
            throw SystemAudioCaptureError.streamFailed(error.localizedDescription)
        }

        self.stream = stream
        print("Echo: system audio capture started for \(application.applicationName)")
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        converter = nil
        outputFormat = nil
        onAudioBuffer = nil
    }

    private func resolveTargetBundleID(preferred: String?, content: SCShareableContent) -> String? {
        let installed = Set(content.applications.compactMap(\.bundleIdentifier))

        if let preferred, installed.contains(preferred) {
            return preferred
        }

        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Self.captureBundleIDs.contains(front),
           installed.contains(front) {
            return front
        }

        return Self.captureBundleIDs.first { installed.contains($0) }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio,
              let handler = onAudioBuffer,
              let pcmBuffer = makePCMBuffer(from: sampleBuffer) else { return }
        handler(pcmBuffer)
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let inputFormat = AVAudioFormat(streamDescription: streamDescriptionPointer) else {
            return nil
        }

        if outputFormat == nil {
            outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: false
            )
            if let outputFormat {
                converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            }
        }

        guard let outputFormat,
              let converter,
              let inputBuffer = makeInputBuffer(from: sampleBuffer, format: inputFormat) else {
            return nil
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, outputBuffer.frameLength > 0 else { return nil }
        return outputBuffer
    }

    private func makeInputBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let audioBufferList = buffer.mutableAudioBufferList
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: audioBufferList
        )
        guard status == noErr else { return nil }
        return buffer
    }
}
