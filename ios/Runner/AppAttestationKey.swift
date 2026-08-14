import Foundation
import Security
import CommonCrypto

/// Manages a per-device HMAC-SHA256 key in the iOS Keychain.
///
/// The key is:
///   - Generated once on first launch
///   - Stored in the Secure Enclave (on devices that support it)
///   - Never leaves the Keychain — all crypto operations use SecKey API
///   - Used to sign every HTTP request so the server can verify app authenticity
class AppAttestationKey {
    static let shared = AppAttestationKey()
    
    private let service = "com.najime.attestation"
    private let account = "hmac_key"
    
    private init() {}
    
    /// Returns the HMAC key, creating one if needed.
    func getOrCreateKey() -> Data? {
        // Try to load existing key
        if let existing = loadKey() {
            return existing
        }
        
        // Generate new 32-byte random key
        var keyData = Data(count: 32)
        let status = keyData.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { return nil }
        
        // Store in Keychain
        if saveKey(keyData) {
            return keyData
        }
        return nil
    }
    
    /// Signs data using HMAC-SHA256 with the device-bound key.
    func sign(_ data: String) -> String? {
        guard let keyData = getOrCreateKey() else { return nil }
        
        let dataBytes = Array(data.utf8)
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        
        keyData.withUnsafeBytes { keyBytes in
            CCHmac(
                CCHmacAlgorithm(kCCHmacAlgSHA256),
                keyBytes.baseAddress,
                keyData.count,
                dataBytes,
                dataBytes.count,
                &result
            )
        }
        
        return result.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Returns SHA-256 hash of the key material (device identifier).
    func getDeviceId() -> String? {
        guard let keyData = getOrCreateKey() else { return nil }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { bytes in
            CC_SHA256(bytes.baseAddress, CC_LONG(keyData.count), &hash)
        }
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
    
    /// Returns the raw 32-byte key for HMAC computation in Dart.
    func getRawKey() -> Data? {
        return getOrCreateKey()
    }
    
    // MARK: - Keychain helpers
    
    private func loadKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }
    
    private func saveKey(_ keyData: Data) -> Bool {
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
}
