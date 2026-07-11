import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Speech

enum PermissionHelper {
    enum Pane: String {
        case microphone = "Privacy_Microphone"
        case speechRecognition = "Privacy_SpeechRecognition"
        case accessibility = "Privacy_Accessibility"
        case automation = "Privacy_Automation"
        case screenRecording = "Privacy_ScreenCapture"

        var settingsURL: URL? {
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")
        }
    }

    struct Status {
        let microphone: Bool
        let speech: Bool
        let accessibility: Bool
        let screenRecording: Bool

        var isReadyForRecording: Bool { microphone && speech }
        var isReadyForShortcuts: Bool { accessibility }
        var isReadyForSystemAudio: Bool { screenRecording }
    }

    static func status() -> Status {
        Status(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speech: SFSpeechRecognizer.authorizationStatus() == .authorized,
            accessibility: AXIsProcessTrusted(),
            screenRecording: SystemAudioCaptureService.hasScreenRecordingPermission()
        )
    }

    static func openSettings(_ pane: Pane) {
        guard let url = pane.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    static func promptAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// 未決定のときだけシステムダイアログを出す（許可済みなら何もしない）
    static func requestMicrophoneIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    static func requestSpeechIfNeeded() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
}
