import Foundation

struct AppBuildInfo {
    let version: String
    let build: String

    static var current: AppBuildInfo {
        AppBuildInfo(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        )
    }

    var displayLabel: String {
        "v\(version) (\(build))"
    }
}
