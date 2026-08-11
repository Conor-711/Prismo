import XCTest
@testable import BSmart

final class BSmartSyncCoordinatorTests: XCTestCase {
    func testPendingOperationSurvivesCoordinatorRecreationAndFlushesAfterRecovery() async throws {
        let suiteName = "BSmartSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = RecordingRemoteSyncClient(isFailing: true)
        let position = PortfolioPosition(
            id: UUID(),
            ticker: "NVDA",
            companyName: "NVIDIA",
            shares: 4,
            averageCost: 110,
            currentPrice: 125,
            entryKind: .position
        )

        let firstCoordinator = BSmartSyncCoordinator(client: client, defaults: defaults)
        await firstCoordinator.enqueuePortfolioUpsert(position)
        let pendingAfterFailure = await firstCoordinator.pendingOperationCount()
        XCTAssertEqual(pendingAfterFailure, 1)

        await client.setFailing(false)
        let restoredCoordinator = BSmartSyncCoordinator(client: client, defaults: defaults)
        await restoredCoordinator.flush()

        let pendingAfterRecovery = await restoredCoordinator.pendingOperationCount()
        let operations = await client.operations
        XCTAssertEqual(pendingAfterRecovery, 0)
        XCTAssertEqual(operations, [.portfolioUpsert(position.id, "NVDA")])
    }

    func testLatestSignalStateReplacesOlderPendingState() async throws {
        let suiteName = "BSmartSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = RecordingRemoteSyncClient(isFailing: true)
        let coordinator = BSmartSyncCoordinator(client: client, defaults: defaults)
        let signalId = UUID()

        await coordinator.enqueueSignalState(SignalUserState(signalId: signalId, isRead: true))
        await coordinator.enqueueSignalState(SignalUserState(
            signalId: signalId,
            isRead: true,
            isSaved: true,
            feedback: .useful
        ))

        let pendingAfterCoalescing = await coordinator.pendingOperationCount()
        XCTAssertEqual(pendingAfterCoalescing, 1)
        await client.setFailing(false)
        await coordinator.flush()

        let operations = await client.operations
        XCTAssertEqual(operations, [.signalState(signalId, true, .useful)])
    }

    func testTelemetryEventsRemainDistinctAndFlushAfterRecovery() async throws {
        let suiteName = "BSmartSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = RecordingRemoteSyncClient(isFailing: true)
        let coordinator = BSmartSyncCoordinator(client: client, defaults: defaults)
        let signalId = UUID()
        let first = ClientTelemetryEvent(
            name: .signalOpened,
            signalId: signalId,
            ticker: "nvda",
            context: .signalDetail
        )
        let second = ClientTelemetryEvent(
            name: .evidenceOpened,
            signalId: signalId,
            ticker: "NVDA",
            evidenceId: UUID(),
            source: .smartAccount,
            context: .signalDetail
        )

        await coordinator.enqueueTelemetry(first)
        await coordinator.enqueueTelemetry(second)
        let pendingBeforeRecovery = await coordinator.pendingOperationCount()
        XCTAssertEqual(pendingBeforeRecovery, 2)

        await client.setFailing(false)
        await coordinator.flush()

        let pendingAfterRecovery = await coordinator.pendingOperationCount()
        let operations = await client.operations
        XCTAssertEqual(pendingAfterRecovery, 0)
        XCTAssertEqual(operations, [.telemetry(first.id), .telemetry(second.id)])
    }

    func testClearPendingOperationsRemovesOfflineOutbox() async throws {
        let suiteName = "BSmartSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = RecordingRemoteSyncClient(isFailing: true)
        let coordinator = BSmartSyncCoordinator(client: client, defaults: defaults)

        await coordinator.enqueueTelemetry(ClientTelemetryEvent(
            name: .dailyDigestOpened,
            context: .dailyDigest
        ))
        let pendingBeforeReset = await coordinator.pendingOperationCount()
        XCTAssertEqual(pendingBeforeReset, 1)

        await coordinator.clearPendingOperations()

        let pendingAfterReset = await coordinator.pendingOperationCount()
        XCTAssertEqual(pendingAfterReset, 0)
    }
}

private enum RecordedSyncOperation: Equatable, Sendable {
    case portfolioUpsert(UUID, String)
    case portfolioDelete(UUID)
    case signalState(UUID, Bool, SignalFeedback?)
    case notificationPreferences
    case deviceRegistration(String)
    case telemetry(UUID)
}

private actor RecordingRemoteSyncClient: BSmartRemoteSyncing {
    private(set) var operations: [RecordedSyncOperation] = []
    private var isFailing: Bool

    init(isFailing: Bool) {
        self.isFailing = isFailing
    }

    func setFailing(_ isFailing: Bool) {
        self.isFailing = isFailing
    }

    func upsertPortfolioEntry(id: UUID, input: PortfolioEntryInput) async throws {
        try failIfNeeded()
        operations.append(.portfolioUpsert(id, input.ticker))
    }

    func deletePortfolioEntry(id: UUID) async throws {
        try failIfNeeded()
        operations.append(.portfolioDelete(id))
    }

    func putSignalUserState(signalId: UUID, input: SignalUserStateInput) async throws {
        try failIfNeeded()
        operations.append(.signalState(signalId, input.isSaved, input.feedback))
    }

    func putNotificationPreferences(_ preferences: NotificationPreferences) async throws {
        try failIfNeeded()
        operations.append(.notificationPreferences)
    }

    func putDeviceRegistration(_ registration: DeviceRegistrationInput) async throws {
        try failIfNeeded()
        operations.append(.deviceRegistration(registration.apnsToken))
    }

    func postTelemetryEvent(_ event: ClientTelemetryEvent) async throws {
        try failIfNeeded()
        operations.append(.telemetry(event.id))
    }

    private func failIfNeeded() throws {
        if isFailing { throw BSmartAPIError.httpStatus(503) }
    }
}
