import SwiftUI

struct SmartHubSearchField: View {
    let prompt: String
    @Binding var query: String
    @State private var draft = ""
    @State private var submitted = ""

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold)).foregroundStyle(BSmartColor.tertiaryText)
            TextField(prompt.bSmartLocalized, text: $draft)
                .font(.subheadline).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("smart.search")
            if !draft.isEmpty {
                Button { draft = ""; submitted = ""; query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BSmartColor.tertiaryText)
                }.accessibilityLabel("Clear".bSmartLocalized)
            }
        }
        .background(BSmartKeyboardInputRegion())
        .onAppear { draft = query; submitted = query }
        .onChange(of: query) { _, value in
            if value != submitted { draft = value; submitted = value }
        }
        .task(id: draft) {
            do {
                if !draft.isEmpty { try await Task.sleep(for: .milliseconds(150)) }
                try Task.checkCancellation()
                submitted = draft
                query = draft
            } catch {}
        }
    }
}
