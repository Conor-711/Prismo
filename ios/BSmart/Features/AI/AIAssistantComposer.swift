import SwiftUI

struct AIAssistantComposer: View {
    @Binding var query: String
    var focus: FocusState<Bool>.Binding
    let isGenerating: Bool
    let submit: () -> Void

    private var canSubmit: Bool {
        !isGenerating && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: BSmartSpacing.small) {
            TextField("Message Mr Collie".bSmartLocalized, text: $query, axis: .vertical)
                .font(.body).foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1...5).focused(focus)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send).onSubmit { if canSubmit { submit() } }
                .padding(.leading, 14).padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel("Message Mr Collie".bSmartLocalized)
                .accessibilityIdentifier("ai.composer")
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(canSubmit ? BSmartColor.onAccent : BSmartColor.tertiaryText)
                    .frame(width: 44, height: 44)
                    .background(canSubmit ? BSmartColor.brand : BSmartColor.disabledControl, in: Circle())
            }
            .buttonStyle(.plain).disabled(!canSubmit)
            .accessibilityLabel("Ask Mr Collie".bSmartLocalized)
            .accessibilityIdentifier("ai.send")
        }
        .padding(5)
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 27))
        .overlay {
            RoundedRectangle(cornerRadius: 27)
                .strokeBorder(focus.wrappedValue ? BSmartColor.brand.opacity(0.6) : BSmartColor.softDivider, lineWidth: 1)
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.vertical, BSmartSpacing.small)
        .background(BSmartKeyboardInputRegion())
        .background(BSmartColor.ink)
        .overlay(alignment: .top) { Divider().overlay(BSmartColor.softDivider) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.input-bar")
    }
}
