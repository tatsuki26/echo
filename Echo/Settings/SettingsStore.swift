import Foundation
import SwiftUI

final class SettingsStore: ObservableObject {
    enum KeychainAccount {
        static let notionToken = "notionToken"
        static let openAIAPIKey = "openAIAPIKey"
    }

    @AppStorage("notionDatabaseID") var notionDatabaseID = ""
    @AppStorage("notionTitleProperty") var notionTitleProperty = "Name"
    @AppStorage("autoStartOnMeetDetection") var autoStartOnMeetDetection = false
    @AppStorage("captureSystemAudio") var captureSystemAudio = true
    @AppStorage("enablePostRecordingDiarization") var enablePostRecordingDiarization = true
    @AppStorage("localeIdentifier") var localeIdentifier = "ja-JP"

    @Published var notionToken = ""
    @Published var openAIAPIKey = ""

    var hasNotionConfiguration: Bool {
        !notionToken.isEmpty && !notionDatabaseID.isEmpty
    }

    var hasOpenAIConfiguration: Bool {
        !openAIAPIKey.isEmpty
    }

    init() {
        notionToken = KeychainHelper.load(account: KeychainAccount.notionToken) ?? ""
        openAIAPIKey = KeychainHelper.load(account: KeychainAccount.openAIAPIKey) ?? ""
    }

    func save() {
        if notionToken.isEmpty {
            KeychainHelper.delete(account: KeychainAccount.notionToken)
        } else {
            KeychainHelper.save(notionToken, account: KeychainAccount.notionToken)
        }

        if openAIAPIKey.isEmpty {
            KeychainHelper.delete(account: KeychainAccount.openAIAPIKey)
        } else {
            KeychainHelper.save(openAIAPIKey, account: KeychainAccount.openAIAPIKey)
        }
    }
}
