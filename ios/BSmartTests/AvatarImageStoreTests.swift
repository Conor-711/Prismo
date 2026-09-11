import UIKit
import XCTest
@testable import BSmart

@MainActor
final class AvatarImageStoreTests: XCTestCase {
    private var directory: URL!
    private let url = URL(string: "https://avatars.example.com/profile.jpg?v=1")!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-tests-\(UUID())")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testVerifiedRedditAvatarsAreBundledAndDoNotMatchOtherPlatforms() throws {
        let url = try XCTUnwrap(RedditAuthorAvatars.url(forDisplayName: "u/Far-East-locker"))
        XCTAssertEqual(url.host, "i.redd.it")
        let asset = try XCTUnwrap(AuthorAvatarAsset.name(for: url))
        XCTAssertNotNil(UIImage(named: asset))
        XCTAssertNil(RedditAuthorAvatars.url(forDisplayName: "Far-East-locker"))
        XCTAssertNil(RedditAuthorAvatars.url(forDisplayName: "@Far-East-locker"))
        XCTAssertNil(RedditAuthorAvatars.url(forDisplayName: "u/unverified-author"))
        let defaultAvatar = try XCTUnwrap(RedditAuthorAvatars.url(forDisplayName: "u/Smart_Money_HQ"))
        XCTAssertNotNil(AuthorAvatarAsset.name(for: defaultAvatar))
    }

    func testConcurrentCellsShareOneRequestAndMemoryCache() async throws {
        let fetcher = StubAvatarFetcher(data: imageData(), delay: .milliseconds(50))
        let store = AvatarImageStore(fetcher: fetcher, directory: directory)
        let url = self.url
        let images = await withTaskGroup(of: AvatarImage?.self, returning: [AvatarImage?].self) { group in
            for _ in 0..<12 { group.addTask { await store.image(for: url) } }
            var results: [AvatarImage?] = []
            for await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(images.compactMap { $0 }.count, 12)
        let cached = await store.image(for: url)
        XCTAssertEqual(cached?.sourceURL, url)
        let count = await fetcher.requests
        XCTAssertEqual(count, 1)
    }

    func testDiskCacheSurvivesStoreRecreationAndDownsamples() async throws {
        let first = AvatarImageStore(fetcher: StubAvatarFetcher(data: imageData(width: 1600)), directory: directory)
        let image = await first.image(for: url)
        XCTAssertEqual(image?.image.cgImage?.width, 256)
        let offline = StubAvatarFetcher(data: Data(), mode: .offline)
        let restarted = AvatarImageStore(fetcher: offline, directory: directory)
        let cached = await restarted.image(for: url)
        XCTAssertNotNil(cached)
        let count = await offline.requests
        XCTAssertEqual(count, 0)
    }

    func testTransientFailureRetriesOnce() async {
        let fetcher = StubAvatarFetcher(data: imageData(), mode: .failOnce)
        let store = AvatarImageStore(fetcher: fetcher, directory: directory, retryDelay: .zero)
        let image = await store.image(for: url)
        XCTAssertNotNil(image)
        let count = await fetcher.requests
        XCTAssertEqual(count, 2)
    }

    func testPermanentFailureHasNoRetryStorm() async {
        let fetcher = StubAvatarFetcher(data: imageData(), mode: .notFound)
        let store = AvatarImageStore(fetcher: fetcher, directory: directory, retryDelay: .zero)
        for _ in 0..<5 {
            let image = await store.image(for: url)
            XCTAssertNil(image)
        }
        let count = await fetcher.requests
        XCTAssertEqual(count, 1)
    }

    func testInvalidImageNeverEntersDiskCache() async throws {
        let fetcher = StubAvatarFetcher(data: Data("<html>not an avatar</html>".utf8))
        let store = AvatarImageStore(fetcher: fetcher, directory: directory)
        let image = await store.image(for: url)
        XCTAssertNil(image)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testGlobalDownloadConcurrencyIsBounded() async {
        let fetcher = StubAvatarFetcher(data: imageData(), delay: .milliseconds(30))
        let store = AvatarImageStore(fetcher: fetcher, directory: directory, maximumConcurrentDownloads: 2)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<8 {
                group.addTask { _ = await store.image(for: URL(string: "https://avatars.example.com/\(i).jpg")!) }
            }
        }
        let maximum = await fetcher.maximumActive
        XCTAssertEqual(maximum, 2)
        let count = await fetcher.requests
        XCTAssertEqual(count, 8)
    }

    func testCancellingOneViewDoesNotCancelSharedResult() async {
        let fetcher = StubAvatarFetcher(data: imageData(), delay: .milliseconds(50))
        let store = AvatarImageStore(fetcher: fetcher, directory: directory)
        let cancelled = Task { await store.image(for: url) }
        let visible = Task { await store.image(for: url) }
        cancelled.cancel()
        _ = await cancelled.value
        let result = await visible.value
        XCTAssertNotNil(result)
        let count = await fetcher.requests
        XCTAssertEqual(count, 1)
    }

    func testURLChangeUsesNewIdentityAndHTTPSIsRequired() async {
        let other = URL(string: "https://avatars.example.com/profile.jpg?v=2")!
        XCTAssertNotEqual(AuthorAvatarAsset.key(for: url), AuthorAvatarAsset.key(for: other))
        let fetcher = StubAvatarFetcher(data: imageData())
        let store = AvatarImageStore(fetcher: fetcher, directory: directory)
        _ = await store.image(for: url)
        let changed = await store.image(for: other)
        XCTAssertEqual(changed?.sourceURL, other)
        let insecure = await store.image(for: URL(string: "http://avatars.example.com/a.jpg")!)
        XCTAssertNil(insecure)
        let count = await fetcher.requests
        XCTAssertEqual(count, 2)
    }

    func testDiskPrunesExpiredAndExcessFiles() throws {
        let now = Date()
        var cache = AvatarDiskCache(directory: directory)
        cache.maximumEntries = 2
        cache.maximumBytes = 16
        cache.lifetime = 60
        cache.write(Data(repeating: 1, count: 8), key: "first", now: now.addingTimeInterval(-20))
        cache.write(Data(repeating: 2, count: 8), key: "second", now: now.addingTimeInterval(-10))
        cache.write(Data(repeating: 3, count: 8), key: "third", now: now)
        XCTAssertNil(cache.read(key: "first", now: now))
        XCTAssertNotNil(cache.read(key: "second", now: now))
        XCTAssertNotNil(cache.read(key: "third", now: now))
        cache.prune(now: now.addingTimeInterval(61))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 0)
    }

    func testBundledAssetsExistAndMatchExactSourceURL() {
        XCTAssertGreaterThan(AuthorAvatarRegistry.keys.count, 50)
        for key in AuthorAvatarRegistry.keys {
            let image = UIImage(named: "AuthorAvatar_\(key)")
            XCTAssertNotNil(image, "Missing compiled avatar: \(key)")
            XCTAssertLessThanOrEqual(image?.cgImage?.width ?? 0, 256)
        }
        let known = URL(string: "https://pbs.twimg.com/profile_images/1356963429530152961/nQG0kjzp_400x400.jpg")!
        XCTAssertNotNil(AuthorAvatarAsset.name(for: known))
        XCTAssertNil(AuthorAvatarAsset.name(for: url))
        XCTAssertNil(AuthorAvatarAsset.name(for: nil))
    }

    private func imageData(width: Int = 32) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: width), format: format)
            .jpegData(withCompressionQuality: 0.9) { context in
                UIColor.green.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: width))
            }
    }
}

private actor StubAvatarFetcher: AvatarImageFetching {
    enum Mode { case success, failOnce, offline, notFound }
    let data: Data
    let mode: Mode
    let delay: Duration
    private(set) var requests = 0
    private(set) var maximumActive = 0
    private var active = 0
    init(data: Data, mode: Mode = .success, delay: Duration = .zero) {
        self.data = data; self.mode = mode; self.delay = delay
    }
    func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if mode == .offline { throw URLError(.notConnectedToInternet) }
        if mode == .failOnce && requests == 1 { throw URLError(.timedOut) }
        try await Task.sleep(for: delay)
        return (data, HTTPURLResponse(url: url, statusCode: mode == .notFound ? 404 : 200,
                                     httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!)
    }
}
