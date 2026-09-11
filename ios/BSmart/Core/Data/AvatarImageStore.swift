import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Immutable, decoded thumbnails may be passed from the image actor to SwiftUI.
struct AvatarImage: @unchecked Sendable {
    let sourceURL: URL
    let image: UIImage
}

enum AuthorAvatarAsset {
    static func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func name(for url: URL?) -> String? {
        guard let url else { return nil }
        let key = key(for: url)
        return AuthorAvatarRegistry.keys.contains(key) ? "AuthorAvatar_\(key)" : nil
    }
}

protocol AvatarImageFetching: Sendable {
    func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionAvatarFetcher: AvatarImageFetching {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }
}

actor AvatarImageStore {
    static let shared = AvatarImageStore()
    private let memory = NSCache<NSURL, MemoryEntry>()
    private var inFlight: [URL: Task<AvatarImage?, Never>] = [:]
    private var retryAfter: [URL: Date] = [:]
    private let fetcher: any AvatarImageFetching
    private let disk: AvatarDiskCache
    private let gate: AvatarDownloadGate
    private let now: @Sendable () -> Date
    private let retryDelay: Duration
    private let failureCooldown: TimeInterval

    init(fetcher: any AvatarImageFetching = URLSessionAvatarFetcher(),
         directory: URL = AvatarDiskCache.defaultDirectory,
         maximumConcurrentDownloads: Int = 4,
         retryDelay: Duration = .milliseconds(500),
         failureCooldown: TimeInterval = 30,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetcher = fetcher
        self.disk = AvatarDiskCache(directory: directory)
        self.gate = AvatarDownloadGate(limit: max(1, maximumConcurrentDownloads))
        self.retryDelay = retryDelay
        self.failureCooldown = failureCooldown
        self.now = now
        memory.countLimit = 160
        memory.totalCostLimit = 24 * 1_024 * 1_024
    }

    func image(for url: URL) async -> AvatarImage? {
        guard url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        if let cached = memory.object(forKey: url as NSURL), cached.expiresAt > now() {
            return cached.value
        }
        if let pending = inFlight[url] { return await pending.value }
        if let date = retryAfter[url], date > now() { return nil }
        // One disappearing cell must not cancel a download shared by other cells.
        let task = Task { await load(url) }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            let cost = (result.image.cgImage?.bytesPerRow ?? 0) * (result.image.cgImage?.height ?? 0)
            memory.setObject(MemoryEntry(value: result, expiresAt: now().addingTimeInterval(86_400)),
                             forKey: url as NSURL, cost: cost)
            retryAfter[url] = nil
        } else {
            retryAfter = retryAfter.filter { $0.value > now() }
            retryAfter[url] = max(retryAfter[url] ?? .distantPast, now().addingTimeInterval(failureCooldown))
        }
        return result
    }

    private func load(_ url: URL) async -> AvatarImage? {
        let key = AuthorAvatarAsset.key(for: url)
        if let data = disk.read(key: key, now: now()), let image = Self.decode(data, url: url) {
            return image
        }
        disk.remove(key: key)
        for attempt in 0..<2 {
            await gate.acquire()
            let response: Result<(Data, HTTPURLResponse), Error>
            do { response = .success(try await fetcher.fetch(url)) }
            catch { response = .failure(error) }
            await gate.release()
            switch response {
            case let .success((data, http)):
                if http.statusCode == 429 {
                    let delay = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
                    retryAfter[url] = now().addingTimeInterval(max(60, delay))
                    return nil
                }
                guard (200..<300).contains(http.statusCode),
                      http.mimeType?.lowercased().hasPrefix("image/") == true,
                      let result = Self.decode(data, url: url) else { return nil }
                if let thumbnail = result.image.jpegData(compressionQuality: 0.86) {
                    disk.write(thumbnail, key: key, now: now())
                }
                return result
            case let .failure(error):
                guard attempt == 0, let error = error as? URLError,
                      [.timedOut, .networkConnectionLost, .cannotConnectToHost,
                       .cannotFindHost, .dnsLookupFailed].contains(error.code) else { return nil }
                try? await Task.sleep(for: retryDelay)
            }
        }
        return nil
    }

    private static func decode(_ data: Data, url: URL) -> AvatarImage? {
        guard !data.isEmpty, data.count <= 4 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 10_000, height <= 10_000,
              width * height <= 20_000_000,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return AvatarImage(sourceURL: url, image: UIImage(cgImage: cgImage))
    }

    private final class MemoryEntry {
        let value: AvatarImage
        let expiresAt: Date
        init(value: AvatarImage, expiresAt: Date) { self.value = value; self.expiresAt = expiresAt }
    }
}

private actor AvatarDownloadGate {
    let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }
    func acquire() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().resume() }
    }
}
