import AppKit
import Foundation

struct DetectedMeetingInfo: Equatable {
    let title: String
    let source: String
    let browserName: String
    let browserBundleID: String?
}

final class MeetingDetector: ObservableObject {
    @Published private(set) var detectedMeeting: DetectedMeetingInfo?
    @Published private(set) var statusMessage = "会議アプリを監視中…"

    private var timer: Timer?
    private var onMeetingDetected: ((DetectedMeetingInfo) -> Void)?
    private let browserNames = [
        "Google Chrome",
        "Safari",
        "Arc",
        "Firefox",
        "Microsoft Edge",
        "Brave Browser"
    ]
    private let meetingAppNames = [
        "zoom.us",
        "Zoom"
    ]

    var isMeetingActive: Bool {
        detectedMeeting != nil
    }

    func setOnMeetingDetected(_ handler: @escaping (DetectedMeetingInfo) -> Void) {
        onMeetingDetected = handler
    }

    func startMonitoring() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.scheduleCheck()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleCheck()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.scheduleCheck()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleCheck() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.findActiveMeeting()
            DispatchQueue.main.async {
                self.applyDetectionResult(result)
            }
        }
    }

    private func applyDetectionResult(_ meeting: DetectedMeetingInfo?) {
        let previous = detectedMeeting

        if let meeting {
            if detectedMeeting != meeting {
                detectedMeeting = meeting
            }
            let message = "\(meeting.source) を検知（\(meeting.browserName)）"
            if statusMessage != message {
                statusMessage = message
            }

            if previous == nil || previous?.title != meeting.title {
                onMeetingDetected?(meeting)
            }
        } else {
            if detectedMeeting != nil {
                detectedMeeting = nil
            }
            let idleMessage = "会議アプリを監視中…（会議タブが見つかりません）"
            if statusMessage != idleMessage {
                statusMessage = idleMessage
            }
        }
    }

    private func findActiveMeeting() -> DetectedMeetingInfo? {
        if let urlResult = MeetingURLDetector.activeMeeting() {
            return DetectedMeetingInfo(
                title: urlResult.title,
                source: urlResult.source,
                browserName: urlResult.browserName,
                browserBundleID: urlResult.browserBundleID
            )
        }

        if let zoomApp = findZoomDesktopApp() {
            return zoomApp
        }

        return findMeetingFromWindowList()
    }

    private func findZoomDesktopApp() -> DetectedMeetingInfo? {
        let zoomApps = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos")
        guard let zoom = zoomApps.first, !zoom.isTerminated else { return nil }

        return DetectedMeetingInfo(
            title: "Zoom 会議",
            source: MeetingPlatform.zoom.rawValue,
            browserName: "Zoom",
            browserBundleID: "us.zoom.xos"
        )
    }

    private func findMeetingFromWindowList() -> DetectedMeetingInfo? {
        let options: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String else { continue }
            let title = (window[kCGWindowName as String] as? String) ?? ""

            if meetingAppNames.contains(where: { ownerName.localizedCaseInsensitiveContains($0) }) {
                return DetectedMeetingInfo(
                    title: cleanZoomTitle(title),
                    source: MeetingPlatform.zoom.rawValue,
                    browserName: ownerName,
                    browserBundleID: "us.zoom.xos"
                )
            }

            guard browserNames.contains(where: { ownerName.localizedCaseInsensitiveContains($0) }) else {
                continue
            }

            if let platform = detectPlatformFromTitle(title) {
                return DetectedMeetingInfo(
                    title: cleanWindowTitle(title, platform: platform),
                    source: platform.rawValue,
                    browserName: ownerName,
                    browserBundleID: nil
                )
            }
        }

        return nil
    }

    private func detectPlatformFromTitle(_ title: String) -> MeetingPlatform? {
        let lower = title.lowercased()
        if lower.contains("meet.google.com") || lower.contains("google meet") { return .googleMeet }
        if lower.contains("zoom") { return .zoom }
        if lower.contains("meet -") || lower.contains("meet –") || lower.hasSuffix("meet") { return .googleMeet }
        return nil
    }

    private func cleanWindowTitle(_ title: String, platform: MeetingPlatform) -> String {
        switch platform {
        case .googleMeet:
            return cleanMeetTitle(title)
        case .zoom:
            return cleanZoomTitle(title)
        }
    }

    private func cleanMeetTitle(_ title: String) -> String {
        var cleaned = title
        let separators = [" - Google Meet", " – Google Meet", " — Google Meet", " | Google Meet", " - Meet", " – Meet"]
        for separator in separators where cleaned.contains(separator) {
            cleaned = cleaned.replacingOccurrences(of: separator, with: "")
        }
        if cleaned.lowercased() == "meet" || cleaned.lowercased() == "google meet" {
            return "Google Meet 会議"
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanZoomTitle(_ title: String) -> String {
        var cleaned = title
        let separators = [" - Zoom", " – Zoom", " | Zoom Meeting", " | Zoom"]
        for separator in separators where cleaned.contains(separator) {
            cleaned = cleaned.replacingOccurrences(of: separator, with: "")
        }
        if cleaned.isEmpty || cleaned.lowercased() == "zoom" {
            return "Zoom 会議"
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
