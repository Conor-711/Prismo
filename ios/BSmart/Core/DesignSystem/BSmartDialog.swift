import SwiftUI

private struct BSmartDialogModifier<Actions: View, Message: View>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let actions: Actions
    let message: Message

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        }
                        .buttonStyle(.bSmartToolbar)
                        .accessibilityLabel("Close".bSmartLocalized)
                        .accessibilityIdentifier("dialog.close")
                    }
                    message.font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    VStack(spacing: 12) {
                        actions.buttonStyle(BSmartDialogActionStyle(isPresented: $isPresented))
                    }
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .bSmartPage()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct BSmartDialogActionStyle: PrimitiveButtonStyle {
    @Binding var isPresented: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            // Trigger first: some bindings clear the pending action on dismissal.
            configuration.trigger()
            isPresented = false
        } label: {
            configuration.label
                .frame(maxWidth: .infinity)
                .foregroundStyle(configuration.role == .destructive ? BSmartColor.bear : BSmartColor.primaryText)
        }
        .buttonStyle(.bSmartSecondary)
    }
}

extension View {
    func bSmartConfirmationDialog<Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> Actions, @ViewBuilder message: () -> Message
    ) -> some View {
        modifier(BSmartDialogModifier(title: title, isPresented: isPresented, actions: actions(), message: message()))
    }

    func bSmartConfirmationDialog<Actions: View>(
        _ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        bSmartConfirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility,
                                actions: actions, message: { EmptyView() })
    }

    func bSmartAlert<Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions, @ViewBuilder message: () -> Message
    ) -> some View {
        bSmartConfirmationDialog(title, isPresented: isPresented, actions: actions, message: message)
    }
}
