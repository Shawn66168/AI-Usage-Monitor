import Foundation
import Security

enum CredentialKind: String, CaseIterable, Sendable {
    case anthropicAdminKey = "anthropic-admin-key"
    case openAIAdminKey = "openai-admin-key"

    var displayName: String {
        switch self {
        case .anthropicAdminKey: "Anthropic Admin Key"
        case .openAIAdminKey: "OpenAI Admin Key"
        }
    }
}

struct KeychainStore: Sendable {
    private let service: String

    init(service: String = "com.xing.ai-usage-monitor") {
        self.service = service
    }

    func contains(_ kind: CredentialKind) -> Bool {
        (try? read(kind)) != nil
    }

    func read(_ kind: CredentialKind) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    func save(_ value: String, for kind: CredentialKind) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var newItem = identity
            attributes.forEach { newItem[$0.key] = $0.value }
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw KeychainError.unhandled(updateStatus)
        }
    }

    func delete(_ kind: CredentialKind) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case invalidData
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "Keychain 憑證資料格式不正確"
        case let .unhandled(status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                "Keychain 錯誤：\(message)"
            } else {
                "Keychain 錯誤代碼：\(status)"
            }
        }
    }
}
