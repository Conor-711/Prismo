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
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var language: AppLanguageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var messages: [AIAssistantChatMessage] = []
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) { messageTimeline }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AIAssistantComposer(query: $query, focus: $isComposerFocused,
                                        isGenerating: isGenerating, submit: submitQuery)
                }
                .background(BSmartColor.ink)
                .navigationTitle("Mr Collie")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(BSmartColor.ink, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: BSmartSpacing.small) {
                            AIAssistantAvatar(size: 26)
                            Text("Mr Collie").font(.headline)
                        }
                    }
                    if let onClose {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: onClose) {
                                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain).foregroundStyle(BSmartColor.primaryText)
                            .accessibilityLabel("Back".bSmartLocalized)
                            .accessibilityIdentifier("ai.back")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: resetConversation) {
                            Image(systemName: "square.and.pencil").font(.system(size: 19, weight: .medium))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(BSmartColor.primaryText)
                        .accessibilityLabel("New conversation".bSmartLocalized)
                        .accessibilityIdentifier("ai.new-conversation")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done".bSmartLocalized, action: dismissKeyboard)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ai.screen")
                .onDisappear {
                    generationTask?.cancel()
                    isGenerating = false
                    isComposerFocused = false
                }
        }
        .bSmartPage()
    }

    private var messageTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BSmartSpacing.xxLarge) {
                    if messages.isEmpty {
                        AIAssistantWelcome(dataAsOf: model.lastDataRefreshAt) { prompt in
                            send(prompt.title.bSmartLocalized,
                                 fallback: { AIResearchAssistant.answer(prompt: prompt, model: model) })
                        }
                    } else {
                        ForEach(messages) { message in messageView(message) }
                    }
                    if isGenerating { typingIndicator }
                    Color.clear.frame(height: 1).id("ai.timeline.bottom")
                }
                .padding(.horizontal, BSmartSpacing.large)
                .padding(.vertical, BSmartSpacing.xLarge)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("ai.timeline")
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isGenerating) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isComposerFocused) { _, focused in
                if focused && !messages.isEmpty { scrollToBottom(proxy) }
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: AIAssistantChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack(alignment: .top) {
                Spacer(minLength: 36)
                Text(message.text ?? "")
                    .font(.body).foregroundStyle(BSmartColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BSmartSpacing.large)
                    .padding(.vertical, BSmartSpacing.medium)
                    .background(BSmartColor.elevated, in: RoundedRectangle(cornerRadius: 18))
            }
            .accessibilityIdentifier("ai.message.user")
        case .assistant:
            if let response = message.response {
                AIAssistantAnswer(response: response, notice: message.notice)
            }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: BSmartSpacing.medium) {
            AIAssistantAvatar(size: 26)
            ProgressView().tint(BSmartColor.brand)
            Text("Reviewing current evidence".bSmartLocalized)
                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("ai.generating")
    }

    private func submitQuery() {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating, !question.isEmpty else { return }
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
            withAnimation(reduceMotion ? nil : BSmartMotion.standard) {
                proxy.scrollTo("ai.timeline.bottom", anchor: .bottom)
            }
        }
    }
}
