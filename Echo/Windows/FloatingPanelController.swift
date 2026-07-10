import AppKit
import SwiftUI

final class FloatingPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    func show<Content: View>(@ViewBuilder content: () -> Content) {
        let rootView = AnyView(content())

        if let hostingView, let panel {
            hostingView.rootView = rootView
            panel.orderFrontRegardless()
            return
        }

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 220)
        hostingView = hosting

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 280
            let y = screenFrame.maxY - 260
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }
}
