import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            if !model.hasFinishedInitialLoad {
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

                    tabLayer(.smart) {
                        SmartHubView()
                    }

                    tabLayer(.portfolio) {
                        PortfolioView()
                    }

                    tabLayer(.ai) {
                        AIAssistantView()
                    }
                }
                .overlay(alignment: .bottom) {
                    if !router.isTabBarHidden {
                        BSmartTabBar(selection: $router.selection)
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
                section: .portfolio,
                label: language.localized("Portfolio"),
                symbol: "chart.pie",
                selectedSymbol: "chart.pie.fill"
            ),
            BSmartTabItem(
                section: .smart,
                label: language.localized("Smart"),
                symbol: "bolt.horizontal.circle",
                selectedSymbol: "bolt.horizontal.circle.fill"
            ),
            BSmartTabItem(
                section: .ai,
                label: "Mr Collie",
                symbol: "sparkles",
                selectedSymbol: "sparkles"
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
            .frame(height: 68)
            .background {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [
                            BSmartColor.tabBarTop.opacity(0.9),
                            BSmartColor.tabBarBottom.opacity(0.86),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    GeometryReader { proxy in
                        let availableWidth = max(0, proxy.size.width - 12)
                        let itemWidth = availableWidth / CGFloat(items.count)

                        selectionCapsule
                            .frame(width: itemWidth, height: 56)
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
            }
            .foregroundStyle(isSelected ? BSmartColor.tabSelectedForeground : BSmartColor.secondaryText.opacity(0.74))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
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
                        BSmartColor.tabSelectionTop.opacity(0.9),
                        BSmartColor.tabSelectionBottom.opacity(0.84),
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
