import SwiftUI

private enum AIAssistantChatRole {
    case user
    case assistant
}

private struct AIAssistantChatMessage: Identifiable {
    let id = UUID()
    let role: AIAssistantChatRole
    let text: String?
    let response: AIAssistantResponse?
    let notice: String?

    static func user(_ text: String) -> AIAssistantChatMessage {
        AIAssistantChatMessage(role: .user, text: text, response: nil, notice: nil)
    }

    static func assistant(
        _ response: AIAssistantResponse,
        notice: String? = nil
    ) -> AIAssistantChatMessage {
        AIAssistantChatMessage(
            role: .assistant,
            text: nil,
            response: response,
            notice: notice
        )
    }
}

struct AIAssistantView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var language: AppLanguageStore
    @State private var query = ""
    @State private var messages: [AIAssistantChatMessage] = []
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @FocusState private var isComposerFocused: Bool

    private let floatingTabBarClearance: CGFloat = 82

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatHeader
                messageTimeline
                composer
                    .padding(.bottom, isComposerFocused ? 0 : floatingTabBarClearance)
            }
            .background(BSmartColor.ink)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done".bSmartLocalized, action: dismissKeyboard)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .accessibilityIdentifier("ai.screen")
            .onDisappear {
                generationTask?.cancel()
                isGenerating = false
                isComposerFocused = false
            }
        }
        .bSmartPage()
    }

    private var chatHeader: some View {
        HStack(spacing: BSmartSpacing.medium) {
            collieAvatar(size: 42)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(BSmartColor.brand)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle().stroke(BSmartColor.ink, lineWidth: 2)
                        }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("Mr Collie")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)

                HStack(spacing: 5) {
                    Circle()
                        .fill(BSmartColor.brand)
                        .frame(width: 5, height: 5)
                    Text("Portfolio intelligence".bSmartLocalized)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BSmartColor.secondaryText)
            }

            Spacer()

            Button(action: resetConversation) {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .frame(width: 38, height: 38)
                    .background(BSmartColor.elevated)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(BSmartColor.line, lineWidth: 0.7)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New conversation".bSmartLocalized)
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.vertical, 11)
        .background(BSmartColor.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismissKeyboard)
    }

    private var messageTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BSmartSpacing.large) {
                    if messages.isEmpty {
                        emptyConversation
                    } else {
                        ForEach(messages) { message in
                            messageView(message)
                        }
                    }

                    if isGenerating {
                        typingIndicator
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("ai.timeline.bottom")
                }
                .padding(.horizontal, BSmartSpacing.large)
                .padding(.vertical, BSmartSpacing.large)
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(
                TapGesture().onEnded(dismissKeyboard)
            )
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isGenerating) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: BSmartSpacing.xLarge) {
            VStack(spacing: 10) {
                collieAvatar(size: 66)
                    .shadow(color: BSmartColor.brand.opacity(0.18), radius: 14)

                Text("What should we look into?".bSmartLocalized)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)

                Text("Ask what changed in your holdings or research a ticker.".bSmartLocalized)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Label(latestDataText, systemImage: "checkmark.shield.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BSmartColor.brand)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, BSmartSpacing.large)

            presetQuestions
        }
        .accessibilityIdentifier("ai.welcome")
    }

    private var presetQuestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested questions".bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)

            VStack(spacing: 8) {
                ForEach(AIAssistantPrompt.allCases) { prompt in
                    Button {
                        send(
                            prompt.title.bSmartLocalized,
                            fallback: { AIResearchAssistant.answer(prompt: prompt, model: model) }
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: prompt.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BSmartColor.pulse)
                                .frame(width: 30, height: 30)
                                .background(BSmartColor.pulse.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            Text(prompt.title.bSmartLocalized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BSmartColor.primaryText)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)

                            Spacer(minLength: 8)

                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .background(BSmartColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(BSmartColor.line, lineWidth: 0.7)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)
                    .accessibilityLabel(prompt.title.bSmartLocalized)
                    .accessibilityIdentifier("ai.prompt.\(prompt.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: AIAssistantChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack(alignment: .top) {
                Spacer(minLength: 52)
                Text(message.text ?? "")
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.pulseInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BSmartSpacing.medium)
                    .padding(.vertical, 11)
                    .background(BSmartColor.pulse)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityIdentifier("ai.message.user")
        case .assistant:
            if let response = message.response {
                assistantRow {
                    responseBubble(response, notice: message.notice)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ai.message.assistant")
            }
        }
    }

    private func responseBubble(
        _ item: AIAssistantResponse,
        notice: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            Text("MR COLLIE")
                .font(.caption2.weight(.black))
                .tracking(0.8)
                .foregroundStyle(BSmartColor.brand)

            Text(item.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ai.response")

            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.primaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if let context = item.context {
                Label(context, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.brand)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BSmartColor.brand.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let notice {
                Label(notice, systemImage: "wifi.exclamationmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BSmartColor.gold)
                    .fixedSize(horizontal: false, vertical: true)
            } else if item.generatedRemotely {
                Label(
                    "Generated by DeepSeek · grounded in bSmart evidence".bSmartLocalized,
                    systemImage: "checkmark.shield.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BSmartColor.brand)
            }

            if !item.evidence.isEmpty {
                evidenceDisclosure(item.evidence)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.pulse)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Next research step".bSmartLocalized)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Text(item.nextStep)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSmartColor.recessed)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            responseActions(item)
        }
        .assistantBubble()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.response")
    }

    private func evidenceDisclosure(_ evidence: [AIAssistantEvidence]) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(Array(evidence.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().overlay(BSmartColor.line)
                    }
                    evidenceRow(item)
                }
            }
            .padding(.top, BSmartSpacing.small)
        } label: {
            Label(
                "%d evidence sources".bSmartLocalized(evidence.count),
                systemImage: "checkmark.shield"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(BSmartColor.brand)
        }
        .tint(BSmartColor.brand)
    }

    private func evidenceRow(_ evidence: AIAssistantEvidence) -> some View {
        HStack(alignment: .top, spacing: BSmartSpacing.small) {
            Image(systemName: evidence.symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(BSmartColor.brand)
                .frame(width: 24, height: 24)
                .background(BSmartColor.brand.opacity(0.09))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(evidence.source.bSmartLocalized)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Spacer()
                    if let metric = evidence.metric {
                        Text(metric)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BSmartColor.pulse)
                            .monospacedDigit()
                    }
                }
                Text(evidence.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(evidence.detail)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, BSmartSpacing.small)
    }

    @ViewBuilder
    private func responseActions(_ item: AIAssistantResponse) -> some View {
        if let signal = item.signal {
            BSmartDetailNavigationLink(id: "ai-signal-\(signal.id)") {
                EventDetailView(signal: signal)
            } label: {
                Label("Open event evidence".bSmartLocalized, systemImage: "arrow.up.right.square")
                    .chatActionStyle()
            }
            .buttonStyle(.plain)
        } else if let ticker = item.ticker,
                  let intelligence = model.intelligence.first(where: {
                      $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame
                  }) {
            BSmartDetailNavigationLink(id: "ai-ticker-\(intelligence.ticker)") {
                TickerIntelligenceView(ticker: intelligence)
            } label: {
                Label("Open ticker research".bSmartLocalized, systemImage: "arrow.up.right.square")
                    .chatActionStyle()
            }
            .buttonStyle(.plain)
        }
    }

    private var typingIndicator: some View {
        assistantRow {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(BSmartColor.secondaryText)
                        .frame(width: 6, height: 6)
                        .opacity(index == 1 ? 1 : 0.45)
                }
                Text("Reviewing current evidence".bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, BSmartSpacing.medium)
            .padding(.vertical, 11)
            .background(BSmartColor.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityIdentifier("ai.generating")
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("Message Mr Collie".bSmartLocalized, text: $query, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1...4)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .focused($isComposerFocused)
                .onSubmit(submitQuery)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    isComposerFocused = true
                }
                .padding(.leading, 8)
                .padding(.vertical, 8)
                .accessibilityLabel("Message Mr Collie".bSmartLocalized)

            Button(action: submitQuery) {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(canSubmit ? BSmartColor.pulseInk : BSmartColor.tertiaryText)
                    .frame(width: 36, height: 36)
                    .background(canSubmit ? BSmartColor.pulse : BSmartColor.recessed)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("Ask Mr Collie".bSmartLocalized)
        }
        .padding(6)
        .background(BSmartColor.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isComposerFocused ? BSmartColor.brand.opacity(0.72) : BSmartColor.line, lineWidth: 0.8)
        }
        .padding(.horizontal, BSmartSpacing.medium)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(BSmartColor.ink)
    }

    private var canSubmit: Bool {
        !isGenerating && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var latestDataText: String {
        guard let date = model.lastDataRefreshAt else {
            return "Waiting for current data".bSmartLocalized
        }
        return "Evidence updated %@".bSmartLocalized(date.bSmartDataTimestamp)
    }

    private func assistantRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: BSmartSpacing.small) {
            collieAvatar(size: 30)
            content()
            Spacer(minLength: 24)
        }
    }

    private func collieAvatar(size: CGFloat) -> some View {
        Image("SmartMoneyBorderCollie")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(BSmartColor.brand.opacity(0.45), lineWidth: 0.8)
            }
    }

    private func submitQuery() {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        query = ""
        isComposerFocused = false
        send(
            question,
            fallback: { AIResearchAssistant.answer(query: question, model: model) }
        )
    }

    private func send(
        _ question: String,
        fallback: @escaping @MainActor () -> AIAssistantResponse
    ) {
        guard !isGenerating else { return }
        let conversation = conversationContext
        messages.append(.user(question))

        // Builds without either direct DeepSeek or the server AI boundary render
        // the grounded local answer immediately so the chat never appears stuck.
        if !model.canQueryMrCollieRemotely {
            messages.append(.assistant(
                fallback(),
                notice: "Mr Collie live service is not connected in this build. Showing an on-device evidence answer.".bSmartLocalized
            ))
            return
        }

        isGenerating = true
        generationTask?.cancel()
        generationTask = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    isGenerating = false
                }
            }
            do {
                let remote = try await model.queryMrCollie(
                    question,
                    locale: language.locale.identifier,
                    conversation: conversation
                )
                guard !Task.isCancelled else { return }
                messages.append(.assistant(
                    AIResearchAssistant.response(from: remote, model: model)
                ))
            } catch {
                guard !Task.isCancelled else { return }
                messages.append(.assistant(
                    fallback(),
                    notice: unavailableMessage(for: error)
                ))
            }
        }
    }

    private func unavailableMessage(for error: Error) -> String {
        if case BSmartAPIError.httpStatus(404) = error {
            return "This server does not have Mr Collie yet. Showing an on-device evidence answer.".bSmartLocalized
        }
        if !model.canQueryMrCollieRemotely {
            return "Live AI is not connected in this build. Showing an on-device evidence answer.".bSmartLocalized
        }
        return "DeepSeek is temporarily unavailable. Showing an on-device evidence answer.".bSmartLocalized
    }

    private var conversationContext: [MrCollieConversationTurn] {
        Array(messages.compactMap { message in
            switch message.role {
            case .user:
                guard let text = message.text else { return nil }
                return MrCollieConversationTurn(role: .user, content: text)
            case .assistant:
                guard let response = message.response else { return nil }
                return MrCollieConversationTurn(
                    role: .assistant,
                    content: "\(response.title)\n\(response.summary)"
                )
            }
        }.suffix(8))
    }

    private func resetConversation() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        messages.removeAll()
        query = ""
        isComposerFocused = false
    }

    private func dismissKeyboard() {
        isComposerFocused = false
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(BSmartMotion.standard) {
                proxy.scrollTo("ai.timeline.bottom", anchor: .bottom)
            }
        }
    }
}

private extension View {
    func assistantBubble() -> some View {
        padding(BSmartSpacing.medium)
            .background(BSmartColor.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BSmartColor.line, lineWidth: 0.7)
            }
    }

    func chatActionStyle() -> some View {
        font(.caption.weight(.bold))
            .foregroundStyle(BSmartColor.pulseInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(BSmartColor.pulse)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
    }
}
