import Foundation

/// View の再生成で @State がリセットされても一度だけ実行する
enum AppLaunchState {
    private static var didBootstrap = false

    static func bootstrapOnce(_ action: @escaping () -> Void) {
        guard !didBootstrap else { return }
        didBootstrap = true
        action()
    }
}
