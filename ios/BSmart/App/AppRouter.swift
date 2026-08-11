import Foundation
import SwiftUI

enum AppSection: String, Hashable {
    case today
    case portfolio
    case research
    case smart
}

enum TodayRoute: Hashable {
    case dailyDigest
}

enum BSmartDeepLink {
    static let signalIDKey = "signalId"
    static let deepLinkKey = "deepLink"

    static func signalURL(for signalID: UUID) -> URL {
        URL(string: "bsmart://signals/\(signalID.uuidString.lowercased())")!
    }

    static func signalID(from url: URL) -> UUID? {
        let components = url.pathComponents.filter { $0 != "/" }

        if url.scheme?.lowercased() == "bsmart",
           url.host?.lowercased() == "signals",
           let value = components.first {
            return UUID(uuidString: value)
        }

        if ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           url.host?.lowercased() == "bsmart.today",
           components.count >= 2,
           components[0].lowercased() == "signals" {
            return UUID(uuidString: components[1])
        }

        return nil
    }

    static func isDailyDigest(_ url: URL) -> Bool {
        let components = url.pathComponents.filter { $0 != "/" }

        if url.scheme?.lowercased() == "bsmart",
           url.host?.lowercased() == "today",
           components.first?.lowercased() == "digest" {
            return true
        }

        return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && url.host?.lowercased() == "bsmart.today"
            && components.count >= 2
            && components[0].lowercased() == "today"
            && components[1].lowercased() == "digest"
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selection: AppSection = .today
    @Published var todayPath = NavigationPath()
    @Published private(set) var pendingSignalID: UUID?

    #if DEBUG
    func applyDebugLaunchSection(from arguments: [String]) {
        guard let argument = arguments.first(where: { $0.hasPrefix("--ui-section=") }),
              let section = AppSection(rawValue: String(argument.dropFirst("--ui-section=".count)))
        else { return }
        selection = section
    }
    #endif

    @discardableResult
    func handle(url: URL) -> Bool {
        if BSmartDeepLink.isDailyDigest(url) {
            openDailyDigest()
            return true
        }

        guard let signalID = BSmartDeepLink.signalID(from: url) else { return false }
        openSignal(signalID)
        return true
    }

    func openDailyDigest() {
        selection = .today
        pendingSignalID = nil
        todayPath = NavigationPath()
        todayPath.append(TodayRoute.dailyDigest)
    }

    func openSignal(_ signalID: UUID) {
        selection = .today
        pendingSignalID = signalID
    }

    func resolvePendingSignal(from signals: [PortfolioSignal]) {
        guard let pendingSignalID,
              let signal = signals.first(where: { $0.id == pendingSignalID })
        else { return }

        todayPath = NavigationPath()
        todayPath.append(signal)
        self.pendingSignalID = nil
    }
}
