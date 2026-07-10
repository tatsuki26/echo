import AppKit
import Foundation

enum MeetingPlatform: String, Equatable {
    case googleMeet = "Google Meet"
    case zoom = "Zoom"
}

struct DetectedMeetingURL: Equatable {
    let url: String
    let browserName: String
    let browserBundleID: String
    let platform: MeetingPlatform

    var title: String { MeetingURLDetector.title(from: url, platform: platform) }
    var source: String { platform.rawValue }
}

/// ブラウザのタブ URL から会議プラットフォームを検知する。
enum MeetingURLDetector {
    static func activeMeeting() -> DetectedMeetingURL? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier,
              let candidate = browserCandidates.first(where: { $0.bundleID == bundleID }) else {
            return nil
        }

        guard isRunning(bundleID: candidate.bundleID) else { return nil }

        guard let url = runAppleScript(candidate.script)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty,
              let platform = platform(for: url) else {
            return nil
        }

        return DetectedMeetingURL(
            url: url,
            browserName: candidate.browserName,
            browserBundleID: candidate.bundleID,
            platform: platform
        )
    }

    static let browserCandidates: [(bundleID: String, browserName: String, script: String)] = [
        (
            "company.thebrowser.Browser",
            "Arc",
            #"tell application "Arc" to if (count of windows) > 0 then return URL of active tab of front window"#
        ),
        (
            "com.google.Chrome",
            "Google Chrome",
            #"tell application "Google Chrome" to if (count of windows) > 0 then return URL of active tab of front window"#
        ),
        (
            "com.apple.Safari",
            "Safari",
            #"tell application "Safari" to if (count of windows) > 0 then return URL of current tab of front window"#
        ),
        (
            "org.mozilla.firefox",
            "Firefox",
            #"tell application "Firefox" to if (count of windows) > 0 then return URL of active tab of front window"#
        ),
        (
            "com.microsoft.edgemac",
            "Microsoft Edge",
            #"tell application "Microsoft Edge" to if (count of windows) > 0 then return URL of active tab of front window"#
        )
    ]

    static func platform(for url: String) -> MeetingPlatform? {
        let lower = url.lowercased()
        if lower.contains("meet.google.com") { return .googleMeet }
        if lower.contains("zoom.us/j/") || lower.contains("zoom.us/w/") || lower.contains("zoom.us/my/") {
            return .zoom
        }
        return nil
    }

    static func title(from url: String, platform: MeetingPlatform) -> String {
        switch platform {
        case .googleMeet:
            if let range = url.range(of: "meet.google.com/") {
                let suffix = String(url[range.upperBound...]).split(separator: "?").first ?? ""
                let meetingCode = suffix.split(separator: "/").first.map(String.init) ?? ""
                if !meetingCode.isEmpty {
                    return "Google Meet (\(meetingCode))"
                }
            }
            return "Google Meet 会議"

        case .zoom:
            if let range = url.range(of: "zoom.us/j/") {
                let suffix = String(url[range.upperBound...]).split(separator: "?").first ?? ""
                let meetingID = suffix.split(separator: "/").first.map(String.init) ?? ""
                if !meetingID.isEmpty {
                    return "Zoom (\(meetingID))"
                }
            }
            if let range = url.range(of: "zoom.us/w/") {
                let suffix = String(url[range.upperBound...]).split(separator: "?").first ?? ""
                if !suffix.isEmpty {
                    return "Zoom Webinar (\(suffix))"
                }
            }
            return "Zoom 会議"
        }
    }

    private static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return output.stringValue
    }
}
