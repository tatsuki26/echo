import AppKit
import SwiftUI

final class MainWindowManager: NSObject, NSWindowDelegate {
    static let shared = MainWindowManager()

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    private weak var appState: AppState?
    private weak var panelCoordinator: PanelCoordinator?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenHistoryNotification),
            name: .echoOpenHistory,
            object: nil
        )
    }

    @objc private func handleOpenHistoryNotification() {
        show()
    }

    func bind(appState: AppState, panelCoordinator: PanelCoordinator) {
        self.appState = appState
        self.panelCoordinator = panelCoordinator
    }

    func show() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.show()
            }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let appState, let panelCoordinator else { return }

        let rootView = AnyView(
            MainWindowRootView()
                .environmentObject(appState)
                .environmentObject(appState.transcriptionService)
                .environmentObject(appState.meetingDetector)
                .environmentObject(panelCoordinator)
        )

        if let hostingView, let window {
            hostingView.rootView = rootView
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 680)
        hostingView = hosting

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Echo"
        window.contentView = hosting
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 560)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 閉じるボタンは非表示にするだけ（アプリは終了しない）
        sender.orderOut(nil)
        return false
    }
}

struct MainWindowRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var panelCoordinator: PanelCoordinator

    var body: some View {
        HistoryWindowView()
            .overlay(alignment: .top) {
                if let bannerMessage = appState.bannerMessage {
                    BannerView(message: bannerMessage) {
                        appState.bannerMessage = nil
                    }
                    .padding(.top, 4)
                }
            }
            .overlay {
                if appState.isProcessing {
                    ZStack {
                        Color.black.opacity(0.08)
                        ProgressView("処理中…")
                            .padding(20)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .onChange(of: appState.isFloatingPanelVisible) { _, _ in
                panelCoordinator.syncFloatingPanel(appState: appState)
            }
            .onReceive(NotificationCenter.default.publisher(for: .echoRecordingStateChanged)) { _ in
                panelCoordinator.syncFloatingPanel(appState: appState)
            }
    }
}

private struct BannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.system(size: 12))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }
}
