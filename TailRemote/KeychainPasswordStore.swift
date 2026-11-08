import Foundation
import Security

struct RemoteCredentialKey: Equatable, Hashable {
    let hostname: String
    let port: UInt16
    let username: String

    init(hostname: String, port: UInt16, username: String) {
        self.hostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.port = port
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var account: String {
        // Array encoding keeps host/port/user boundaries unambiguous.
        let components = [hostname, String(port), username]
        return (try! JSONEncoder().encode(components)).base64EncodedString()
    }
}

protocol RemotePasswordStoring {
    func password(for key: RemoteCredentialKey) throws -> String?
    func save(_ password: String, for key: RemoteCredentialKey) throws
    func removePassword(for key: RemoteCredentialKey) throws
}

struct KeychainPasswordStore: RemotePasswordStoring {
    let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "TailRemote") + ".remote-passwords.v1") {
        self.service = service
    }

    func password(for key: RemoteCredentialKey) throws -> String? {
        var request = query(for: key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = perform { SecItemCopyMatching(request as CFDictionary, &result) }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return password
    }

    func save(_ password: String, for key: RemoteCredentialKey) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let request = query(for: key)
        var status = perform { SecItemUpdate(request as CFDictionary, attributes as CFDictionary) }
        if status == errSecItemNotFound {
            let item = request.merging(attributes) { _, new in new }
            status = perform { SecItemAdd(item as CFDictionary, nil) }
            if status == errSecDuplicateItem {
                status = perform { SecItemUpdate(request as CFDictionary, attributes as CFDictionary) }
            }
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func removePassword(for key: RemoteCredentialKey) throws {
        let status = perform { SecItemDelete(query(for: key) as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    /// Rebuilds can return errSecMissingEntitlement (-34018) once, before the
    /// process is fully entitled. A second attempt on that status only.
    private func perform(_ operation: () -> OSStatus) -> OSStatus {
        let status = operation()
        guard status == KeychainError.missingEntitlement else { return status }
        return operation()
    }

    // The app's default access group is intentional. Setting kSecAttrAccessGroup
    // requires the Keychain Sharing entitlement and would orphan passwords saved
    // before that group existed. No LAContext is stored or passed in: these items
    // are unlocked with the device, not Face ID, and a cancelled context reused
    // for the next read fails every later attempt. A missing item is nil. User
    // cancel and auth failure throw KeychainError.isCancelled instead.
    private func query(for key: RemoteCredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}

struct KeychainError: Error, Equatable {
    let status: OSStatus

    static let missingEntitlement = OSStatus(-34018)

    var isMissingItem: Bool { status == errSecItemNotFound }

    /// Face ID or a system auth sheet was dismissed or failed. The item may still exist.
    var isCancelled: Bool { status == errSecUserCanceled || status == errSecAuthFailed }
}
