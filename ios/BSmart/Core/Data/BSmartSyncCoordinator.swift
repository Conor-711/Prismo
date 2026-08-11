import Foundation

struct PortfolioEntryInput: Codable, Equatable {
    let ticker: String
    let companyName: String
    let entryKind: PortfolioEntryKind
    let shares: Double?
    let averageCost: Double?
    let portfolioWeight: Double?

    init(position: PortfolioPosition) {
        ticker = position.ticker
        companyName = position.companyName
        entryKind = position.resolvedKind
        shares = position.isPosition && position.shares > 0 ? position.shares : nil
        averageCost = position.isPosition && position.averageCost > 0 ? position.averageCost : nil
        portfolioWeight = position.isPosition ? position.portfolioWeight : nil
    }
}

struct SignalUserStateInput: Codable, Equatable {
    let isRead: Bool
    let isSaved: Bool
    let isIgnored: Bool
    let feedback: SignalFeedback?

    init(state: SignalUserState) {
        isRead = state.isRead
        isSaved = state.isSaved
        isIgnored = state.isIgnored
        feedback = state.feedback
    }
}

struct DeviceRegistrationInput: Codable, Equatable {
    let apnsToken: String
    let environment: String
    let appVersion: String
    let locale: String
    let timeZone: String
}

enum ClientTelemetryName: String, Codable {
    case notificationOpened = "notification_opened"
    case dailyDigestOpened = "daily_digest_opened"
    case signalOpened = "signal_opened"
    case evidenceOpened = "evidence_opened"
    case signalSaved = "signal_saved"
    case signalIgnored = "signal_ignored"
    case signalFeedback = "signal_feedback"
}

enum ClientTelemetryContext: String, Codable {
    case push
    case today
    case signalDetail = "signal_detail"
    case dailyDigest = "daily_digest"
    case research
    case opportunity
    case smart
}

struct ClientTelemetryEvent: Codable, Equatable {
    let id: UUID
    let name: ClientTelemetryName
    let occurredAt: Date
    let signalId: UUID?
    let ticker: String?
    let evidenceId: UUID?
    let source: SignalEvidenceSource?
    let context: ClientTelemetryContext

    init(
        id: UUID = UUID(),
        name: ClientTelemetryName,
        occurredAt: Date = Date(),
        signalId: UUID? = nil,
        ticker: String? = nil,
        evidenceId: UUID? = nil,
        source: SignalEvidenceSource? = nil,
        context: ClientTelemetryContext
    ) {
        self.id = id
        self.name = name
        self.occurredAt = occurredAt
        self.signalId = signalId
        self.ticker = ticker?.uppercased()
        self.evidenceId = evidenceId
        self.source = source
        self.context = context
    }
}

struct ClientTelemetryBatch: Codable {
    let events: [ClientTelemetryEvent]
}

protocol BSmartRemoteSyncing: Sendable {
    func upsertPortfolioEntry(id: UUID, input: PortfolioEntryInput) async throws
    func deletePortfolioEntry(id: UUID) async throws
    func putSignalUserState(signalId: UUID, input: SignalUserStateInput) async throws
    func putNotificationPreferences(_ preferences: NotificationPreferences) async throws
    func putDeviceRegistration(_ registration: DeviceRegistrationInput) async throws
    func postTelemetryEvent(_ event: ClientTelemetryEvent) async throws
}

private enum BSmartSyncOperationKind: String, Codable {
    case portfolioUpsert
    case portfolioDelete
    case signalState
    case notificationPreferences
    case deviceRegistration
    case telemetry
}

private struct BSmartSyncOperation: Codable, Identifiable {
    let id: UUID
    let kind: BSmartSyncOperationKind
    let entityId: String
    let payload: Data?
    let enqueuedAt: Date

    var deduplicationKey: String {
        switch kind {
        case .portfolioUpsert, .portfolioDelete: "portfolio:\(entityId)"
        case .signalState: "signal:\(entityId)"
        case .notificationPreferences: "notification-preferences"
        case .deviceRegistration: "device-registration"
        case .telemetry: "telemetry:\(entityId)"
        }
    }
}

private final class BSmartSyncOperationStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey = "bsmart.pending-sync-operations.v1"
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> [BSmartSyncOperation] {
        lock.withLock {
            guard let data = defaults.data(forKey: storageKey),
                  let operations = try? JSONDecoder().decode([BSmartSyncOperation].self, from: data)
            else { return [] }
            return operations.sorted { $0.enqueuedAt < $1.enqueuedAt }
        }
    }

    func upsert(_ operation: BSmartSyncOperation) {
        lock.withLock {
            var operations = decodedOperations()
            operations.removeAll { $0.deduplicationKey == operation.deduplicationKey }
            operations.append(operation)
            persist(operations)
        }
    }

    func remove(id: UUID) {
        lock.withLock {
            var operations = decodedOperations()
            operations.removeAll { $0.id == id }
            persist(operations)
        }
    }

    func clear() {
        lock.withLock {
            defaults.removeObject(forKey: storageKey)
        }
    }

    private func decodedOperations() -> [BSmartSyncOperation] {
        guard let data = defaults.data(forKey: storageKey),
              let operations = try? JSONDecoder().decode([BSmartSyncOperation].self, from: data)
        else { return [] }
        return operations
    }

    private func persist(_ operations: [BSmartSyncOperation]) {
        guard !operations.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(operations) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

actor BSmartSyncCoordinator {
    private let client: BSmartRemoteSyncing
    private let store: BSmartSyncOperationStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var isFlushing = false

    init(client: BSmartRemoteSyncing, defaults: UserDefaults = .standard) {
        self.client = client
        self.store = BSmartSyncOperationStore(defaults: defaults)
        self.encoder = BSmartJSONCoding.makeEncoder()
        self.decoder = BSmartJSONCoding.makeDecoder()
    }

    func enqueuePortfolioUpsert(_ position: PortfolioPosition) async {
        enqueue(
            kind: .portfolioUpsert,
            entityId: position.id.uuidString,
            payload: try? encoder.encode(PortfolioEntryInput(position: position))
        )
        await flush()
    }

    func enqueuePortfolioDelete(id: UUID) async {
        enqueue(kind: .portfolioDelete, entityId: id.uuidString, payload: nil)
        await flush()
    }

    func enqueueSignalState(_ state: SignalUserState) async {
        enqueue(
            kind: .signalState,
            entityId: state.signalId.uuidString,
            payload: try? encoder.encode(SignalUserStateInput(state: state))
        )
        await flush()
    }

    func enqueueNotificationPreferences(_ preferences: NotificationPreferences) async {
        enqueue(
            kind: .notificationPreferences,
            entityId: "current",
            payload: try? encoder.encode(preferences)
        )
        await flush()
    }

    func enqueueDeviceRegistration(_ registration: DeviceRegistrationInput) async {
        enqueue(
            kind: .deviceRegistration,
            entityId: "current",
            payload: try? encoder.encode(registration)
        )
        await flush()
    }

    func enqueueTelemetry(_ event: ClientTelemetryEvent) async {
        enqueue(
            kind: .telemetry,
            entityId: event.id.uuidString,
            payload: try? encoder.encode(event)
        )
        await flush()
    }

    func bootstrap(portfolio: [PortfolioPosition], signalStates: [SignalUserState]) async {
        for position in portfolio {
            enqueue(
                kind: .portfolioUpsert,
                entityId: position.id.uuidString,
                payload: try? encoder.encode(PortfolioEntryInput(position: position))
            )
        }
        for state in signalStates {
            enqueue(
                kind: .signalState,
                entityId: state.signalId.uuidString,
                payload: try? encoder.encode(SignalUserStateInput(state: state))
            )
        }
        await flush()
    }

    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while let operation = store.load().first {
            do {
                try await execute(operation)
                store.remove(id: operation.id)
            } catch {
                return
            }
        }
    }

    func pendingOperationCount() -> Int {
        store.load().count
    }

    func clearPendingOperations() {
        store.clear()
    }

    private func enqueue(kind: BSmartSyncOperationKind, entityId: String, payload: Data?) {
        store.upsert(BSmartSyncOperation(
            id: UUID(),
            kind: kind,
            entityId: entityId,
            payload: payload,
            enqueuedAt: Date()
        ))
    }

    private func execute(_ operation: BSmartSyncOperation) async throws {
        switch operation.kind {
        case .portfolioUpsert:
            try await client.upsertPortfolioEntry(
                id: try uuid(from: operation.entityId),
                input: try decode(PortfolioEntryInput.self, from: operation)
            )
        case .portfolioDelete:
            try await client.deletePortfolioEntry(id: try uuid(from: operation.entityId))
        case .signalState:
            try await client.putSignalUserState(
                signalId: try uuid(from: operation.entityId),
                input: try decode(SignalUserStateInput.self, from: operation)
            )
        case .notificationPreferences:
            try await client.putNotificationPreferences(
                try decode(NotificationPreferences.self, from: operation)
            )
        case .deviceRegistration:
            try await client.putDeviceRegistration(
                try decode(DeviceRegistrationInput.self, from: operation)
            )
        case .telemetry:
            try await client.postTelemetryEvent(
                try decode(ClientTelemetryEvent.self, from: operation)
            )
        }
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from operation: BSmartSyncOperation
    ) throws -> Value {
        guard let payload = operation.payload else { throw BSmartAPIError.invalidResponse }
        return try decoder.decode(type, from: payload)
    }

    private func uuid(from value: String) throws -> UUID {
        guard let identifier = UUID(uuidString: value) else { throw BSmartAPIError.invalidResponse }
        return identifier
    }
}
