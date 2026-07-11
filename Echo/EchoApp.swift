import SwiftData
import SwiftUI

@main
struct EchoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarDropdownView()
                .environmentObject(appModel.appState)
                .environmentObject(appModel.appState.transcriptionService)
                .environmentObject(appModel.appState.meetingDetector)
                .environmentObject(appModel.panelCoordinator)
        } label: {
            MenuBarLaunchLabel()
                .environmentObject(appModel.menuBarIconController)
        }
        .menuBarExtraStyle(.window)

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

        MainWindowManager.shared.bind(appState: appState, panelCoordinator: panelCoordinator)

        Task { @MainActor in
            await appState.bootstrap()
            MainWindowManager.shared.show()
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
                    .environmentObject(appState.transcriptionService)
            }
        } else {
            floatingPanel.hide()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
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
