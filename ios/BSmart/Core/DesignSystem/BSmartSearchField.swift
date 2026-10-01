import SwiftUI

private struct BSmartSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(BSmartColor.secondaryText)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            Button { text = "" } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bSmartPlain)
            .accessibilityLabel("Clear".bSmartLocalized)
            .opacity(text.isEmpty ? 0 : 1)
            .disabled(text.isEmpty)
            .accessibilityHidden(text.isEmpty)
        }
        .font(.subheadline)
        .padding(.leading, 12)
        .frame(height: 44)
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.line, lineWidth: 0.75) }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(BSmartColor.ink)
    }
}

extension View {
    func bSmartSearchable(text: Binding<String>, prompt: String) -> some View {
        safeAreaInset(edge: .top, spacing: 0) { BSmartSearchField(text: text, prompt: prompt) }
    }
}
