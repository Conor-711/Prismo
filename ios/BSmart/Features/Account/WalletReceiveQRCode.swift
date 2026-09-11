import SwiftUI
import CoreImage.CIFilterBuiltins

enum WalletReceiveQRCode {
    static func image(address: WalletReceiveAddress) -> CGImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(address.value.utf8)
        generator.correctionLevel = "M"
        guard let code = generator.outputImage else { return nil }
        // Preserve whole modules and a white quiet zone, independent of app appearance.
        let extent = code.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        let padded = code.composited(over: white).cropped(to: extent)
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

struct WalletReceiveQRCodeView: View {
    let address: WalletReceiveAddress
    @State private var bitmap: CGImage?

    var body: some View {
        Group {
            if let bitmap {
                Image(decorative: bitmap, scale: 1)
                    .resizable().interpolation(.none).scaledToFit()
            } else {
                Text("QR code unavailable. Use the address below.".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(.black).multilineTextAlignment(.center)
                    .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 224, height: 224)
        .background(.white)
        .accessibilityLabel("Receiving address QR code".bSmartLocalized)
        .accessibilityIdentifier("wallet.receive-qr")
        .task(id: address) { bitmap = WalletReceiveQRCode.image(address: address) }
    }
}
