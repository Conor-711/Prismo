import Foundation
import Darwin

struct FundingJournalFiles: Sendable {
    let directory: URL
    var database: URL { directory.appendingPathComponent("transactions.sqlite") }

    static func applicationDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true).appendingPathComponent("FundingJournal", isDirectory: true)
    }

    static func databasePath(_ url: URL) throws -> String {
        // iOS container paths can start with /var, a system alias for /private/var.
        // Resolve only the parent; SQLite must still reject a substituted database symlink.
        guard let parent = realpath(url.deletingLastPathComponent().path, nil) else {
            throw FundingJournalError.unavailable
        }
        defer { free(parent) }
        // Keep the POSIX path: Foundation URL normalization can restore the /var alias.
        return String(cString: parent) + "/" + url.lastPathComponent
    }

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        try protect(directory, directory: true)
        let lock = directory.appendingPathComponent("journal.lock")
        let descriptor = Darwin.open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw FundingJournalError.unavailable }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw FundingJournalError.busy }
        defer { flock(descriptor, LOCK_UN) }
        try protect(lock, directory: false)
        return try operation()
    }

    func databaseExists() throws -> Bool {
        do {
            let values = try database.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            guard values.isSymbolicLink == false, values.isRegularFile == true,
                  (values.fileSize ?? 0) <= 256 * 1_024 * 1_024 else { throw FundingJournalError.integrity }
            return true
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return false
        }
    }

    func protect(_ url: URL, directory: Bool) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        guard values.isSymbolicLink == false, directory ? values.isDirectory == true : values.isRegularFile == true else {
            throw FundingJournalError.integrity
        }
        try FileManager.default.setAttributes([.posixPermissions: directory ? 0o700 : 0o600,
                                               .protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var protectedURL = url
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try protectedURL.setResourceValues(resources)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let excluded = try protectedURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        #if targetEnvironment(simulator)
        // The simulator's macOS filesystem does not implement iOS Data Protection.
        let requiresDataProtection = false
        #else
        let requiresDataProtection = true
        #endif
        try Self.validateProtection(attributes, excludedFromBackup: excluded, directory: directory,
                                    requiresDataProtection: requiresDataProtection)
    }

    static func validateProtection(_ attributes: [FileAttributeKey: Any], excludedFromBackup: Bool?,
                                   directory: Bool, requiresDataProtection: Bool) throws {
        let protection = (attributes[.protectionKey] as? FileProtectionType)?.rawValue
            ?? attributes[.protectionKey] as? String
        guard (attributes[.posixPermissions] as? NSNumber)?.intValue == (directory ? 0o700 : 0o600),
              excludedFromBackup == true,
              !requiresDataProtection || protection == FileProtectionType.complete.rawValue else {
            throw FundingJournalError.unavailable
        }
    }
}
