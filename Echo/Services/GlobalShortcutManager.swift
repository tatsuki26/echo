import AppKit
import Foundation

final class GlobalShortcutManager {
    var onToggleRecording: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func register() {
        unregister()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            DispatchQueue.main.async {
                _ = self?.handle(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains([.command, .shift]), event.charactersIgnoringModifiers?.lowercased() == "s" {
            onToggleRecording?()
            return true
        }

        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "o" {
            onOpenHistory?()
            return true
        }

        if flags.contains(.command), event.charactersIgnoringModifiers == "," {
            onOpenSettings?()
            return true
        }

        return false
    }
}
