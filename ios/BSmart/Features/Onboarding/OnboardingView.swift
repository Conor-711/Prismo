import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    let isPreview: Bool
    let onFinishPreview: (() -> Void)?
    @State private var page = 0
    @State private var selectedCall: TodayRepresentativeStory.Call?
    @State private var isShowingOrderPreview = false
    @State private var isFinishing = false
    @State private var finishError: String?

    private let pageCount = 3
    private var story: TodayRepresentativeStory? { OnboardingFeaturedStory.story }

    init(isPreview: Bool = false, onFinishPreview: (() -> Void)? = nil) {
        self.isPreview = isPreview
        self.onFinishPreview = onFinishPreview
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $page) {
                OnboardingDiscoveryPage(story: story) { selectedCall = $0 }
                    .tag(0)
                OnboardingTrackingPage(
                    story: story,
                    isFollowing: isFollowingFeatured,
                    onToggleFollow: toggleFeaturedFollow
                )
                .tag(1)
                OnboardingTradePage(
                    story: story,
                    sample: .sample,
                    onPreview: { isShowingOrderPreview = true }
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(BSmartMotion.standard, value: page)

            bottomBar
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.top, BSmartSpacing.small)
        .padding(.bottom, BSmartSpacing.small)
        .background(BSmartColor.ink.ignoresSafeArea())
        .sheet(item: $selectedCall) { call in
            if let story {
                OnboardingCallPreview(story: story, call: call)
            }
        }
        .sheet(isPresented: $isShowingOrderPreview) {
            if let story {
                OnboardingOrderPreview(
                    story: story,
                    margin: tradeDraft.margin,
                    leverage: tradeDraft.leverage
                )
            }
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("onboarding.screen")
                .allowsHitTesting(false)
        }
        .bSmartPage()
    }

    private var topBar: some View {
        HStack {
            BSmartWordmark(fontSize: 20)
            Spacer()
            if page < pageCount - 1 {
                Button("Skip".bSmartLocalized) {
                    finish()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
                .accessibilityIdentifier("onboarding.skip")
            }
        }
        .frame(height: 36)
    }

    private var bottomBar: some View {
        VStack(spacing: BSmartSpacing.small) {
            if let finishError {
                Text(finishError)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.bear)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: BSmartSpacing.large) {
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? BSmartColor.brand : BSmartColor.strongLine)
                        .frame(width: index == page ? 20 : 6, height: 6)
                        .animation(BSmartMotion.standard, value: page)
                }
            }

            Button(action: continueFlow) {
                HStack {
                    if isFinishing { ProgressView().tint(BSmartColor.ink) }
                    Text(primaryButtonTitle.bSmartLocalized)
                    Spacer()
                    Image(systemName: page == pageCount - 1 ? "checkmark" : "arrow.right")
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, BSmartSpacing.large)
                .frame(maxWidth: .infinity, minHeight: 50)
                .bSmartActionSurface(cornerRadius: BSmartRadius.control)
            }
            .disabled(isFinishing)
            .accessibilityIdentifier(page == pageCount - 1 ? "onboarding.finish" : "onboarding.continue")
            }
        }
        .padding(.top, BSmartSpacing.small)
    }

    private var primaryButtonTitle: String {
        page == pageCount - 1 ? "Open bSmart" : "Continue"
    }

    private var isFollowingFeatured: Bool {
        guard let story else { return false }
        return model.isFollowingSmartAccount(story.account.id)
    }

    private var tradeDraft: OnboardingTradeDraft {
        .sample
    }

    private func toggleFeaturedFollow() {
        guard let story else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        model.toggleSmartAccountFollow(story.account.id)
    }

    private func continueFlow() {
        UISelectionFeedbackGenerator().selectionChanged()
        if page < pageCount - 1 {
            withAnimation(BSmartMotion.standard) { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        if isPreview {
            onFinishPreview?()
        } else {
            guard !isFinishing else { return }
            isFinishing = true
            finishError = nil
            Task {
                defer { isFinishing = false }
                do { try await model.completeInitialOnboardingRemotely() }
                catch { finishError = "Couldn't save your setup. Please try again.".bSmartLocalized }
            }
        }
    }
}

struct OnboardingPageFrame<Content: View>: View {
    let step: Int
    let title: String
    let content: Content

    init(
        step: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.step = step
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                Text(String(format: "%02d / 03", step))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(BSmartColor.secondaryText)

                Text(title.bSmartLocalized)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, BSmartSpacing.medium)
        .padding(.bottom, BSmartSpacing.small)
    }
}
