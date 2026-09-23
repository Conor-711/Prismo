import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.scenePhase) private var phase
    @State private var floatingNavigationFrame = CGRect.null
    @StateObject private var globalChatUnread = GlobalChatUnreadStore()

    private var globalChatPollKey: String {
        "\(account.identity?.id.uuidString ?? "signed-out"):\(phase == .active):\(router.selection == .friends)"
    }

    var body: some View {
        Group {
            #if DEBUG
            if DebugDataScenario.launched != nil && model.isUsingDemoData
                && !ProcessInfo.processInfo.arguments.contains("--ui-auth-gate") {
                // Existing UI fixtures contain only bundled demo content, never live data.
                appContent
            } else {
                AppSessionGate { appContent }
            }
            #else
            AppSessionGate { appContent }
            #endif
        }
    }

    private var appContent: some View {

        Group {
            if !model.hasResolvedAccountState, let error = model.accountStateError {
                BSmartErrorView(message: error) {
                    Task { await model.restoreAccountState() }
                }
            } else if !model.hasResolvedAccountState || !model.hasFinishedInitialLoad {
                BSmartLoadingView()
            } else if let errorMessage = model.errorMessage, model.signals.isEmpty {
                BSmartErrorView(message: errorMessage) {
                    Task { await model.retry() }
                }
            } else if !model.hasCompletedPortfolioSetup {
                OnboardingView()
            } else {
                ZStack {
                    tabLayer(.today) {
                        TodayView()
                    }

                    tabLayer(.portfolio) {
                        PortfolioView()
                    }

                    tabLayer(.feed) {
                        TradeFeedView()
                    }

                    tabLayer(.search) {
                        AppSearchView()
                    }

                    tabLayer(.friends) {
                        FriendsView()
                    }
                }
                .environment(\.bSmartFloatingNavigationFrame, floatingNavigationFrame)
                .overlay(alignment: .bottom) {
                    if !router.isTabBarHidden {
                        BSmartTabBar(selection: $router.selection)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                floatingNavigationFrame = frame
                            }
                    }
                }
                .environmentObject(globalChatUnread)
                .task(id: globalChatPollKey) {
                    let accountID = account.identity?.id
                    globalChatUnread.activate(accountID: accountID)
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-chat-unread-fixture") {
                        globalChatUnread.showFixtureUnread()
                        return
                    }
#endif
                    guard let accountID, phase == .active else { return }
                    while !Task.isCancelled {
                        if !globalChatUnread.isViewing {
                            do {
                                let page = try await NativeSocialClient(account: account)
                                    .chat(.global, accountID: accountID)
                                guard !Task.isCancelled, account.identity?.id == accountID else { return }
                                globalChatUnread.ingest(page.items, accountID: accountID)
                            } catch {
                                // Keep the last known unread state until the next successful check.
                            }
                        }
                        do { try await Task.sleep(for: .seconds(router.selection == .friends ? 8 : 20)) } catch { return }
                    }
                }
            }
        }
        .bSmartPage()
    }

    private func tabLayer<Content: View>(
        _ section: AppSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = router.selection == section

        return content()
            .ignoresSafeArea(.keyboard, edges: isSelected ? [] : .bottom)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .zIndex(isSelected ? 1 : 0)
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}

private struct BSmartTabBar: View {
    @Binding var selection: AppSection

    @EnvironmentObject private var language: AppLanguageStore
    @EnvironmentObject private var globalChatUnread: GlobalChatUnreadStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isKeyboardVisible = false

    private var items: [BSmartTabItem] {
        [
            BSmartTabItem(
                section: .today,
                label: language.localized("Today"),
                symbol: "house",
                selectedSymbol: "house.fill"
            ),
            BSmartTabItem(
                section: .search,
                label: language.localized("Search"),
                symbol: "magnifyingglass",
                selectedSymbol: "magnifyingglass"
            ),
            BSmartTabItem(
                section: .feed,
                label: language.localized("Discover"),
                symbol: "rectangle.stack",
                selectedSymbol: "rectangle.stack.fill"
            ),
            BSmartTabItem(
                section: .friends,
                label: language.localized("Friends"),
                symbol: "person.2",
                selectedSymbol: "person.2.fill"
            ),
            BSmartTabItem(
                section: .portfolio,
                label: language.localized("My profile"),
                symbol: "person.crop.circle",
                selectedSymbol: "person.crop.circle.fill"
            ),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    tabButton(item)
                }
            }
            .padding(6)
            .frame(height: 64)
            .background {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [
                            BSmartColor.tabBarTop.opacity(colorScheme == .dark ? 0.9 : 0.98),
                            BSmartColor.tabBarBottom.opacity(colorScheme == .dark ? 0.86 : 0.98),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    GeometryReader { proxy in
                        let availableWidth = max(0, proxy.size.width - 12)
                        let itemWidth = availableWidth / CGFloat(items.count)

                        selectionCapsule
                            .frame(width: itemWidth, height: 52)
                            .offset(
                                x: 6 + itemWidth * CGFloat(selectedIndex),
                                y: 6
                            )
                            .animation(BSmartMotion.spring, value: selection)
                            .allowsHitTesting(false)
                    }
                }
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [BSmartColor.tabBarOutline, BSmartColor.tabBarOutline.opacity(0.34)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: BSmartColor.floatingShadow, radius: 13, x: 0, y: 7)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("app.tabbar")
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 4)
        .opacity(isKeyboardVisible ? 0 : 1)
        .allowsHitTesting(!isKeyboardVisible)
        .animation(BSmartMotion.quick, value: isKeyboardVisible)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    private func tabButton(_ item: BSmartTabItem) -> some View {
        let isSelected = selection == item.section

        return Button {
            guard !isSelected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selection = item.section
        } label: {
            ZStack {
                Image(systemName: isSelected ? item.selectedSymbol : item.symbol)
                    .font(.system(size: 25, weight: isSelected ? .bold : .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 31, height: 31)
                    .overlay(alignment: .topTrailing) {
                        if item.section == .friends && globalChatUnread.hasUnread {
                            Circle().fill(BSmartColor.bear)
                                .frame(width: 7, height: 7)
                                .offset(x: 3, y: -2)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .foregroundStyle(isSelected ? BSmartColor.tabSelectedForeground : BSmartColor.tabInactiveForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityValue(item.section == .friends && globalChatUnread.hasUnread
                            ? "Unread messages".bSmartLocalized : "")
        .accessibilityIdentifier("app.tab.\(item.section.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedIndex: Int {
        items.firstIndex(where: { $0.section == selection }) ?? 0
    }

    private var selectionCapsule: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        BSmartColor.tabSelectionTop.opacity(colorScheme == .dark ? 0.9 : 1),
                        BSmartColor.tabSelectionBottom.opacity(colorScheme == .dark ? 0.84 : 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [BSmartColor.tabSelectionOutline, BSmartColor.tabSelectionOutline.opacity(0.32)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: BSmartColor.compactShadow, radius: 4, x: 0, y: 2)
    }
}

private struct BSmartTabItem: Identifiable {
    let section: AppSection
    let label: String
    let symbol: String
    let selectedSymbol: String

    var id: AppSection { section }
}
