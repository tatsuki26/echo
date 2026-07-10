import Foundation

extension Bundle {
    var echoVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    var echoBuildString: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
