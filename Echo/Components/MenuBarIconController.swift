import Foundation
import SwiftUI

/// メニューバーアイコン専用の軽量アニメーション状態。
/// AppState 全体を MenuBarExtra の label で読むと再描画ループになるため分離する。
final class MenuBarIconController: ObservableObject {
    static let barCount = 6

    @Published private(set) var isRecording = false
    @Published private(set) var animationTime: TimeInterval = 0
    /// 実際の入力音量から作る波形（右端が最新）。録音中のみ更新する
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: barCount)
    @Published private(set) var elapsedText = "0:00"
    @Published private(set) var hasWarning = false

    /// 入力レベルの取得元（TranscriptionService.levelMeter）
    var levelSource: (() -> AudioLevelMeter.Snapshot)?

    private var timer: Timer?
    private var recordingStartedAt = Date()

    func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording

        if recording {
            recordingStartedAt = Date()
            startAnimation()
        } else {
            stopAnimation()
            animationTime = 0
            levels = Array(repeating: 0, count: Self.barCount)
            elapsedText = "0:00"
            hasWarning = false
        }
    }

    func setWarning(_ warning: Bool) {
        guard hasWarning != warning else { return }
        hasWarning = warning
    }

    private func startAnimation() {
        stopAnimation()
        animationTime = Date().timeIntervalSinceReferenceDate

        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard isRecording else { return }
        let now = Date()
        animationTime = now.timeIntervalSinceReferenceDate

        let level = CGFloat(levelSource?().combinedLevel ?? 0)
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next

        let elapsed = Int(now.timeIntervalSince(recordingStartedAt))
        let text = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        if text != elapsedText {
            elapsedText = text
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}
