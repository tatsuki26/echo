import Foundation
import SwiftUI

/// メニューバーアイコン専用の軽量アニメーション状態。
/// AppState 全体を MenuBarExtra の label で読むと再描画ループになるため分離する。
final class MenuBarIconController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var animationTime: TimeInterval = 0

    private var timer: Timer?

    func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording

        if recording {
            startAnimation()
        } else {
            stopAnimation()
            animationTime = 0
        }
    }

    private func startAnimation() {
        stopAnimation()
        animationTime = Date().timeIntervalSinceReferenceDate

        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.animationTime = Date().timeIntervalSinceReferenceDate
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}
