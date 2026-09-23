import SwiftUI

struct SmartFilterOptions<Value: Hashable>: View {
    let title: String
    let identifier: String
    let options: [Value]
    @Binding var selection: Value
    let optionTitle: (Value) -> String
    var showsPlatform = false
    @ScaledMetric(relativeTo: .subheadline) private var minimumWidth = 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.bSmartLocalized)
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 8)], spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let name = optionTitle(option)
                    let selected = selection == option
                    Button { selection = option } label: {
                        HStack(spacing: 6) {
                            if showsPlatform && !name.hasPrefix("All ") {
                                SmartPlatformMark(platform: name, size: 16)
                            }
                            Text(name.bSmartLocalized)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(selected ? BSmartColor.brand : BSmartColor.tertiaryText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? BSmartColor.brand : BSmartColor.primaryText)
                        .background(selected ? BSmartColor.brand.opacity(0.10) : BSmartColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selected ? BSmartColor.brand : BSmartColor.line, lineWidth: 0.75)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name.bSmartLocalized)
                    .accessibilityIdentifier("smart.filter.\(identifier).\(name)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}
