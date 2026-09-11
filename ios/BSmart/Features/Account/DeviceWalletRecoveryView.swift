import SwiftUI
import UIKit

struct DeviceWalletRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var wallet: DeviceWalletStore
    @State private var words: [String] = []
    @State private var phrase = ""
    @State private var confirming = false
    @State private var errorMessage: String?
    @State private var captured = UIScreen.main.isCaptured
    @State private var revealRevision = UUID()
    @FocusState private var inputFocused: Bool

    private var restoring: Bool {
        if case .recoveryRequired = wallet.state { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: restoring ? "key" : "lock.shield")
                    .font(.system(size: 32)).foregroundStyle(BSmartColor.brand)
                Text((restoring ? "Restore your wallet" : "Protect your wallet").bSmartLocalized)
                    .font(.system(.title2, weight: .bold))
                Text("Anyone with these 24 words can take your funds. Keep them offline. bSmart will never ask you to send them.".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)

                if captured {
                    Label("Stop screen recording or sharing to view your recovery phrase.".bSmartLocalized,
                          systemImage: "eye.slash").font(.headline)
                } else if restoring || confirming {
                    Text((restoring ? "Enter your 24 recovery words" : "Re-enter all 24 words to verify your backup").bSmartLocalized)
                        .font(.headline)
                    SecureField("Recovery phrase".bSmartLocalized, text: $phrase)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.asciiCapable).textContentType(nil)
                        .font(.body).padding(16)
                        .background(BSmartColor.secondaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .focused($inputFocused)
                        .accessibilityIdentifier("wallet.recovery-input")
                        .onChange(of: phrase) { _, newValue in
                            if newValue.utf8.count > 512 { phrase = String(newValue.prefix(512)) }
                        }
                    primary(restoring ? "Restore wallet" : "Verify backup") {
                        inputFocused = false
                        Task {
                            let success = restoring ? await wallet.restore(phrase: phrase)
                                : await wallet.confirmRecovery(phrase: phrase)
                            phrase = ""
                            if success { dismiss() }
                        }
                    }.disabled(phrase.split(whereSeparator: \.isWhitespace).count != 24 || wallet.isBusy)
                } else if !words.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 10) {
                                Text("\(index + 1)").font(.caption.monospacedDigit())
                                    .foregroundStyle(BSmartColor.secondaryText).frame(width: 22, alignment: .trailing)
                                Text(word).font(.system(.body, design: .monospaced, weight: .medium))
                                    .minimumScaleFactor(0.85).lineLimit(1)
                                Spacer(minLength: 0)
                            }.padding(.vertical, 9)
                        }
                    }
                    .privacySensitive()
                    primary("I wrote them down") {
                        clearSecrets()
                        confirming = true
                    }
                } else {
                    primary("Reveal recovery phrase") {
                        let operation = UUID()
                        revealRevision = operation
                        Task {
                            do {
                                let result = try await wallet.revealRecovery()
                                // Face ID may briefly make the scene inactive; never reveal in the app switcher.
                                for _ in 0..<10 where scenePhase == .inactive && revealRevision == operation {
                                    try await Task.sleep(for: .milliseconds(50))
                                }
                                guard revealRevision == operation, scenePhase == .active, !captured else { return }
                                words = result
                            } catch {
                                guard revealRevision == operation else { return }
                                errorMessage = (error as? DeviceWalletError)?.errorDescription
                            }
                        }
                    }.disabled(wallet.isBusy)
                }

                if wallet.isBusy { ProgressView().frame(maxWidth: .infinity) }
                if let message = errorMessage ?? wallet.errorMessage {
                    Text(message).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Recovery phrase".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { clearSecrets(); dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close".bSmartLocalized)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done".bSmartLocalized) { inputFocused = false }
            }
        }
        .overlay {
            if scenePhase != .active {
                BSmartColor.ink.ignoresSafeArea()
                    .overlay(Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(BSmartColor.brand))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { clearSecrets(invalidateReveal: phase == .background) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            captured = UIScreen.main.isCaptured
            if captured { clearSecrets() }
        }
        .onDisappear { clearSecrets() }
        .onChange(of: wallet.state) { _, state in
            if case .locked = state { clearSecrets(); dismiss() }
        }
        .privacySensitive()
        .interactiveDismissDisabled(wallet.isBusy)
        .accessibilityIdentifier("wallet.recovery-screen")
    }

    private func clearSecrets(invalidateReveal: Bool = true) {
        if invalidateReveal { revealRevision = UUID() }
        words.removeAll(keepingCapacity: false)
        phrase = ""
        inputFocused = false
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.bSmartLocalized).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(BSmartColor.onAccent)
                .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}
