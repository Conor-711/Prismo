import Foundation

enum RedditAuthorAvatars {
    private static let urls: [String: String] = {
        guard let file = Bundle.main.url(forResource: "reddit-author-avatars", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()

    // Only explicit Reddit handles may use the fallback; display names can collide across platforms.
    static func url(forDisplayName name: String) -> URL? {
        let handle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard handle.hasPrefix("u/"), let value = urls[String(handle.dropFirst(2))],
              let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }
}
