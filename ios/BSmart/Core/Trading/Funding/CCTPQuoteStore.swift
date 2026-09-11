import Foundation

@MainActor
final class CCTPQuoteStore: ObservableObject {
    @Published private(set) var schedule: CCTPFeeSchedule?
    @Published private(set) var isLoading = false
    @Published private(set) var error: CCTPFundingError?
    private let client: any CCTPFeeProviding
    private var revision = UUID()

    init(client: any CCTPFeeProviding = CCTPFeeClient()) { self.client = client }

    func refresh() async {
        let request = UUID()
        revision = request
        isLoading = true
        error = nil
        schedule = nil
        do {
            let value = try await client.schedule()
            try Task.checkCancellation()
            try value.validate(now: Date())
            guard revision == request else { return }
            schedule = value
        } catch {
            guard revision == request else { return }
            if !(error is CancellationError) { self.error = (error as? CCTPFundingError) ?? .unavailable }
        }
        guard revision == request else { return }
        isLoading = false
    }

    func clear() {
        revision = UUID()
        schedule = nil
        error = nil
        isLoading = false
    }
}
