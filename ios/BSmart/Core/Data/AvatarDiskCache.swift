import Foundation

/// Called only from the image actor, never from the rendering/main actor.
struct AvatarDiskCache {
    static let defaultDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("bSmart/AuthorAvatars", isDirectory: true)
    let directory: URL
    var maximumBytes: Int = 32 * 1_024 * 1_024
    var maximumEntries: Int = 512
    var lifetime: TimeInterval = 30 * 86_400

    func read(key: String, now: Date) -> Data? {
        let url = location(key)
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let date = values.contentModificationDate, now.timeIntervalSince(date) <= lifetime,
              let size = values.fileSize, size > 0, size <= 4 * 1_024 * 1_024 else { return nil }
        return try? Data(contentsOf: url)
    }

    func write(_ data: Data, key: String, now: Date) {
        guard data.count <= maximumBytes else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: location(key), options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: location(key).path)
            prune(now: now)
        } catch { /* A full disk must not prevent an already decoded avatar from rendering. */ }
    }

    func remove(key: String) { try? FileManager.default.removeItem(at: location(key)) }

    func prune(now: Date) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)) ?? []
        var entries: [(url: URL, date: Date, size: Int)] = []
        for url in urls where url.pathExtension == "jpg" {
            guard let values = try? url.resourceValues(forKeys: keys),
                  let date = values.contentModificationDate, now.timeIntervalSince(date) <= lifetime,
                  let size = values.fileSize else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            entries.append((url, date, size))
        }
        entries.sort { $0.date > $1.date }
        var bytes = 0
        for (index, entry) in entries.enumerated() {
            bytes += entry.size
            if index >= maximumEntries || bytes > maximumBytes {
                try? FileManager.default.removeItem(at: entry.url)
            }
        }
    }

    private func location(_ key: String) -> URL { directory.appendingPathComponent(key).appendingPathExtension("jpg") }
}
