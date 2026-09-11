import UIKit
import UniformTypeIdentifiers

@MainActor
enum WalletReceiveClipboard {
    static func copy(_ address: WalletReceiveAddress, to pasteboard: UIPasteboard = .general, now: Date = Date()) {
        pasteboard.setItems([[UTType.utf8PlainText.identifier: address.value]],
                            options: [.localOnly: true, .expirationDate: now.addingTimeInterval(300)])
    }
}
