import SwiftUI

struct BSmartSelectionOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }

    init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }
}

struct BSmartSegmentedControl<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [BSmartSelectionOption<Value>]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(selection == option.value ? BSmartColor.primaryText : BSmartColor.secondaryText)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selection == option.value ? BSmartColor.elevated : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .bottom) {
                            if selection == option.value {
                                Rectangle().fill(BSmartColor.brand).frame(height: 2).padding(.horizontal, 8)
                            }
                        }
                }
                .buttonStyle(.bSmartPlain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BSmartColor.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .transaction { $0.animation = nil }
    }
}

struct BSmartMenu<Actions: View, Label: View>: View {
    let title: String
    let actions: Actions
    let label: Label
    @State private var isPresented = false

    init(_ title: String = "Options".bSmartLocalized,
         @ViewBuilder content: () -> Actions, @ViewBuilder label: () -> Label) {
        self.title = title
        actions = content()
        self.label = label()
    }

    var body: some View {
        Button { isPresented = true } label: { label }
            .bSmartConfirmationDialog(title, isPresented: $isPresented) { actions }
    }
}

struct BSmartOptionPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [BSmartSelectionOption<Value>]

    var body: some View {
        BSmartMenu(title) {
            ForEach(options) { option in
                Button { selection = option.value } label: {
                    HStack {
                        Text(option.title)
                        Spacer()
                        if selection == option.value { Image(systemName: "checkmark") }
                    }
                }
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.title ?? title)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.bSmartSecondary)
        .accessibilityLabel(title)
    }
}

struct BSmartToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                Capsule()
                    .fill(configuration.isOn ? BSmartColor.brand : BSmartColor.elevated)
                    .overlay(Capsule().strokeBorder(BSmartColor.line))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(BSmartColor.primaryText).frame(width: 20, height: 20).padding(2)
                    }
                    .frame(width: 44, height: 24)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bSmartPlain)
        .accessibilityValue((configuration.isOn ? "On" : "Off").bSmartLocalized)
        .opacity(isEnabled ? 1 : 0.5)
        .transaction { $0.animation = nil }
    }
}

extension ToggleStyle where Self == BSmartToggleStyle {
    static var bSmartSwitch: BSmartToggleStyle { .init() }
}
