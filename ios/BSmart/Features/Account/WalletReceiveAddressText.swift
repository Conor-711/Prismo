import SwiftUI

struct WalletReceiveAddressText: UIViewRepresentable {
    let address: WalletReceiveAddress
    @ScaledMetric(relativeTo: .callout) private var fontSize = 16

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        // Text layout must never insert a hyphen into a receiving address.
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .center
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = address.value
        label.accessibilityLabel = address.value
        label.textColor = UIColor(BSmartColor.primaryText)
        label.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}
