import SwiftUI

private struct SmartSubjectDestination: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let payload: TickerSmartActivityPayload
    @State private var isPresented = false
    @Namespace private var transition

    private var identity: String {
        switch payload {
        case .account(let update): "account.\(update.authorId)"
        case .money(let movement): "money.\(movement.accountId)"
        }
    }

    private var usesZoomTransition: Bool {
        if case .account = payload { return false }
        return true
    }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { isPresented = true })
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("subject.\(identity)")
            .accessibilityAction { isPresented = true }
            .bSmartMatchedTransitionSource(id: identity, in: transition)
            .fullScreenCover(isPresented: $isPresented) {
                NavigationStack {
                    switch payload {
                    case .account(let update):
                        SmartAccountDetailView(account: model.smartAccountProfile(for: update))
                    case .money(let movement):
                        if let signal = model.smartMoney.first(where: {
                            $0.id.caseInsensitiveCompare(movement.accountId) == .orderedSame
                                || $0.resolvedAddress.caseInsensitiveCompare(movement.accountId) == .orderedSame
                        }) {
                            SmartMoneyDetailView(signal: signal)
                        } else {
                            SmartMoneyObservedProfile(movement: movement)
                        }
                    }
                }
                .bSmartZoomNavigationTransition(sourceID: identity, in: transition, enabled: usesZoomTransition)
            }
    }
}

/// An unranked account still has an identity and observed activity, not invented performance.
private struct SmartMoneyObservedProfile: View {
    @EnvironmentObject private var model: AppModel
    let movement: SmartMoneyMovement

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(movement.publicIdentity.displayName).font(.headline)
                        Text(movement.accountId).font(.caption).textSelection(.enabled)
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                TickerSmartActivityFeed(activities: model.smartMoneyMovements
                    .filter { $0.accountId.caseInsensitiveCompare(movement.accountId) == .orderedSame }
                    .sorted { $0.observedAt > $1.observedAt }
                    .map { TickerSmartActivityItem(payload: .money($0)) }, framed: false)
            }
            .padding(20)
        }
        .navigationTitle("Smart Money")
        .bSmartDetailPage()
        .bSmartPage()
    }
}

extension View {
    func bSmartSubjectDestination(_ update: SmartAccountUpdate) -> some View {
        modifier(SmartSubjectDestination(payload: .account(update)))
    }

    func bSmartSubjectDestination(_ movement: SmartMoneyMovement) -> some View {
        modifier(SmartSubjectDestination(payload: .money(movement)))
    }

    func bSmartSubjectDestination(_ activity: TickerSmartActivityItem) -> some View {
        modifier(SmartSubjectDestination(payload: activity.payload))
    }
}
