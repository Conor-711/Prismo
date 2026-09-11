# Wallet Core binary pin

This small local Swift package uses the **official 4.8.1 release binaries**, not
a fork of the cryptographic implementation. The upstream source tag's root
`Package.swift` still references 4.2.9; it is not a reliable binary-version pin.

Source: [Trust Wallet Core 4.8.1 release](https://github.com/trustwallet/wallet-core/releases/tag/4.8.1),
published September 7, 2026. The URLs and SHA-256 checksums in this manifest match
the [release manifest](https://github.com/trustwallet/wallet-core/releases/download/4.8.1/Package.swift)
and the GitHub release asset digests. SwiftPM verifies downloaded artifacts.

- WalletCore SHA-256: `872fa3c67460897d2a2685a73677140db4291e872df527d21c147d9cf297b645`
- WalletCoreSwiftProtobuf SHA-256: `ba60483570abe0579df97348aaf528d1dfd2d5bdc07a8d8e0e352313b0e413c8`

Only the adapter in `Core/Wallet/DeviceWalletCryptography.swift` imports WalletCore.
Entropy is explicitly generated with Apple's `SecRandomCopyBytes`, not a browser
or JavaScript RNG. BIP39, derivation, Ethereum address hashing and EIP-191 signing
remain upstream implementations. No generic message/transaction signing UI exists.

An integrity pin is not an independent security audit or reproducible-build proof.
Production release still needs provenance/security review of this exact binary,
transitive license attribution and vulnerability review; do not replace it with
an unpinned branch or automatically upgrade it in routine UI work.
