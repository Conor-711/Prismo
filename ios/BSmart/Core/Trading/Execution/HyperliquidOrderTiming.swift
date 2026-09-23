import Foundation
import OSLog

// Local timing only: no wallet, token, order payload, signature or position data.
@MainActor
final class HyperliquidOrderTiming {
    private static let logger = Logger(subsystem: "today.bsmart.ios", category: "OrderLatency")
    private var started: ContinuousClock.Instant?
    private var identifier = ""

    func begin() {
        started = .now
        identifier = UUID().uuidString
        mark("start")
    }

    func mark(_ stage: String) {
        guard let started else { return }
        let parts = started.duration(to: .now).components
        let milliseconds = parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000
        Self.logger.notice("order=\(self.identifier, privacy: .public) stage=\(stage, privacy: .public) elapsed_ms=\(milliseconds)")
    }

    func end(_ outcome: String) { mark(outcome); started = nil }

    func measure<T>(_ stage: String, operation: () async throws -> T) async rethrows -> T {
        mark(stage + ".start")
        defer { mark(stage + ".end") }
        return try await operation()
    }
}
