import SwiftData
import SwiftUI

@main
struct EchoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        // 注意: body 内で appState の @Published プロパティを読むと
        // MenuBarExtra が無限再描画ループに入るため、environmentObject の注入のみ行う
        MenuBarExtra {
            MenuBarDropdownView()
                .environmentObject(appModel.appState)
                .environmentObject(appModel.panelCoordinator)
        } label: {
            MenuBarLaunchLabel()
                .environmentObject(appModel.menuBarIconController)
        }
        .menuBarExtraStyle(.window)

        Window("Echo — 履歴", id: "history") {
            RootView()
                .environmentObject(appModel.appState)
                .environmentObject(appModel.panelCoordinator)
        }
        .modelContainer(EchoModelContainer.shared)
        .defaultSize(width: 440, height: 460)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Echo") {
                Button("履歴を開く") {
                    appModel.appState.openHistoryWindow()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("文字起こしの開始/停止") {
                    Task {
                        await appModel.appState.toggleRecording()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("環境設定…") {
                    appModel.appState.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("環境設定", id: "settings") {
            SettingsView(settingsStore: appModel.appState.settingsStore)
                .environmentObject(appModel.appState)
        }
        .defaultSize(width: 520, height: 560)

        Window("デザインカタログ", id: "catalog") {
            DesignCatalogView()
                .environmentObject(appModel.appState)
        }
        .defaultSize(width: 900, height: 800)
    }
}

final class AppModel: ObservableObject {
    let menuBarIconController = MenuBarIconController()
    let appState: AppState
    let panelCoordinator = PanelCoordinator()

    init() {
        let store = MeetingStore(modelContext: ModelContext(EchoModelContainer.shared))
        appState = AppState(
            transcriptionService: TranscriptionService(),
            meetingStore: store,
            meetingDetector: MeetingDetector(),
            settingsStore: SettingsStore(),
            menuBarIconController: menuBarIconController
        )

        Task { @MainActor in
            await appState.bootstrap()
            panelCoordinator.syncFloatingPanel(appState: appState)
        }
    }
}

final class PanelCoordinator: ObservableObject {
    let floatingPanel = FloatingPanelController()

    func syncFloatingPanel(appState: AppState) {
        if appState.isFloatingPanelVisible {
            floatingPanel.show {
                FloatingPanelView()
                    .environmentObject(appState)
            }
        } else {
            floatingPanel.hide()
        }
    }
}

private struct RootView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var panelCoordinator: PanelCoordinator

    var body: some View {
        HistoryWindowView()
            .overlay(alignment: .top) {
                if let bannerMessage = appState.bannerMessage {
                    BannerView(message: bannerMessage) {
                        appState.bannerMessage = nil
                    }
                    .padding(.top, 8)
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
            .onAppear {
                AppLaunchState.bootstrapOnce {
                    panelCoordinator.syncFloatingPanel(appState: appState)
                }
            }
            .onChange(of: appState.isFloatingPanelVisible) { _, _ in
                panelCoordinator.syncFloatingPanel(appState: appState)
            }
            .onChange(of: appState.isRecording) { _, isRecording in
                if isRecording {
                    appState.isFloatingPanelVisible = true
                    panelCoordinator.syncFloatingPanel(appState: appState)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .echoRecordingStateChanged)) { _ in
                panelCoordinator.syncFloatingPanel(appState: appState)
            }
            .onChange(of: appState.isSettingsPresented) { _, presented in
                if presented {
                    openWindow(id: "settings")
                    appState.isSettingsPresented = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .echoOpenHistory)) { _ in
                openWindow(id: "history")
            }
            .onReceive(NotificationCenter.default.publisher(for: .echoOpenSettings)) { _ in
                openWindow(id: "settings")
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 二重起動時は既存インスタンスを前面に出して終了する
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
            if let existing = others.first {
                existing.activate(options: [.activateIgnoringOtherApps])
                NSApp.terminate(nil)
                return
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            for window in NSApp.windows where window.title.contains("履歴") {
                window.orderOut(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum EchoModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            StoredMeeting.self,
            StoredTranscriptLine.self,
            StoredActionItem.self
        ])

        do {
            return try ModelContainer(for: schema)
        } catch {
            print("Echo: persistent ModelContainer failed (\(error)), falling back to in-memory.")
            let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: memoryConfig)
            } catch {
                fatalError("Failed to create in-memory ModelContainer: \(error)")
            }
        }
    }()
}
