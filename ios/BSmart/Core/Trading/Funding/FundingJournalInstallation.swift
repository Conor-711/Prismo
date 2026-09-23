import Foundation

/// Binds the container's ledger to a Keychain namespace that can outlive an app install.
struct FundingJournalInstallation: Codable {
    let version: Int
    let namespace: UUID?

    // Called under FundingJournalFiles.withLock, including on first creation.
    static func service(base: String, marker: URL, files: FundingJournalFiles) throws -> String {
        let installation: Self
        let values: URLResourceValues?
        do {
            values = try marker.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            values = nil
        }
        if let values {
            guard values.isSymbolicLink == false, values.isRegularFile == true,
                  let size = values.fileSize, size > 0, size <= 512 else { throw FundingJournalError.integrity }
            try files.protect(marker, directory: false)
            guard let stored = try? JSONDecoder().decode(Self.self, from: Data(contentsOf: marker)),
                  stored.version == 1 else { throw FundingJournalError.integrity }
            installation = stored
        } else {
            // Existing databases retain their original anchor. A container without a database
            // starts a separate ledger; surviving legacy anchors are never deleted or rewritten.
            installation = Self(version: 1, namespace: try files.databaseExists() ? nil : UUID())
            try JSONEncoder().encode(installation).write(to: marker, options: [.atomic, .completeFileProtection])
            try files.protect(marker, directory: false)
        }
        return installation.namespace.map { base + ".installation." + $0.uuidString.lowercased() } ?? base
    }
}
