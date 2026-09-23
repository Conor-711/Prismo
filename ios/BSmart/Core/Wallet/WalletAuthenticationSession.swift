import Foundation
import LocalAuthentication
import UIKit

// Reuse authentication, never key bytes. Backgrounding and sign-out end the session.
final class WalletAuthenticationSession: @unchecked Sendable {
    static let shared = WalletAuthenticationSession()
    static let reuseDuration: TimeInterval = 300
    private let lock = NSLock()
    private var contexts: [String: (context: LAContext, created: TimeInterval)] = [:]
    private var observers: [NSObjectProtocol] = []
    private let uptime: @Sendable () -> TimeInterval

    init(uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.protectedDataWillBecomeUnavailableNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.invalidate()
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver); invalidate() }

    func context(scope: String) -> LAContext {
        lock.withLock {
            let now = uptime()
            if let entry = contexts[scope], now >= entry.created,
               now - entry.created < Self.reuseDuration { return entry.context }
            contexts.removeValue(forKey: scope)?.context.invalidate()
            let context = LAContext()
            context.localizedReason = "Unlock your bSmart wallet".bSmartLocalized
            contexts[scope] = (context, now)
            return context
        }
    }

    func invalidate() {
        lock.withLock {
            contexts.values.forEach { $0.context.invalidate() }
            contexts.removeAll()
        }
    }
}
