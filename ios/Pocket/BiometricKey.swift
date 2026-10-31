import Foundation
import CryptoKit
import LocalAuthentication
import Security

/// A P-256 key that lives in the Secure Enclave and can only sign after Face ID.
/// The private key never leaves the chip; the server stores only the public half.
enum BiometricKey {
    private static let service = "com.yiqunxu.pocket.biometric"
    private static let account = "device-key"

    static var available: Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return false }
        return context.biometryType == .faceID || context.biometryType == .touchID
    }

    static func create() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            nil
        ) else {
            throw PocketError.message("无法创建生物识别访问控制")
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: false, accessControl: access)
        save(key)
        return key
    }

    static func load() -> SecureEnclave.P256.Signing.PrivateKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        query[kSecUseOperationPrompt as String] = "用 Face ID 解锁 Pocket"
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
    }

    static func save(_ key: SecureEnclave.P256.Signing.PrivateKey) {
        let data = key.dataRepresentation
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
        SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ] as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }

    static func publicKeyBase64(_ key: SecureEnclave.P256.Signing.PrivateKey) -> String {
        key.publicKey.derRepresentation.base64EncodedString()
    }

    /// Face ID prompt happens inside `signature(for:)`.
    static func sign(_ key: SecureEnclave.P256.Signing.PrivateKey, _ message: String) throws -> String {
        let signature = try key.signature(for: Data(message.utf8))
        return signature.derRepresentation.base64EncodedString()
    }
}
