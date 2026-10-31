import Foundation

/// Nonsecret marker used only to distinguish an ordinary restart from a restored backup.
/// Credentials never use this fallback. Losing the cache conservatively requires review.
enum InstallationIdentity {
  static func current() throws -> String {
    if let data = SessionVault.read("installation"), let value = String(data: data, encoding: .utf8)
    {
      return value
    }
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: "TripSplitInstallation", directoryHint: .isDirectory)
    let file = directory.appending(path: "identity")
    if let data = try? Data(contentsOf: file), let value = String(data: data, encoding: .utf8),
      UUID(uuidString: value) != nil
    {
      return value
    }
    let value = UUID().uuidString
    do {
      try SessionVault.write(Data(value.utf8), key: "installation")
      return value
    } catch {
      // Unsigned simulators cannot access Keychain. Normal app data still works;
      // a release's session secrets continue to require valid signing/Keychain access.
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data(value.utf8).write(
        to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      var excluded = URLResourceValues()
      excluded.isExcludedFromBackup = true
      var marker = file
      try marker.setResourceValues(excluded)
      return value
    }
  }
}
