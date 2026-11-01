import Foundation
import Security
import TripSplitDomain

package enum SessionVault {
  package static let service = "it.tripspl.TripSplit"
  package static func read(_ key: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }
  package static func write(_ data: Data, key: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false,
    ]
    let updated = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else {
      throw ServiceError(
        code: "keychain",
        message:
          "Secure device storage is unavailable. Unlock your device and try again. A signed build is required for Apple sessions."
      )
    }
    let item: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: data,
    ]
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw ServiceError(
        code: "keychain",
        message: "Secure device storage is unavailable. Please unlock your device and try again.")
    }
  }
  package static func delete(_ key: String) {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: key,
      ] as CFDictionary)
  }
}
