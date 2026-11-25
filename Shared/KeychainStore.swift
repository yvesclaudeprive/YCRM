import Foundation
import Security

/// Trousseau iOS : le jeton API reste sur cet iPhone (ni synchronisé iCloud, ni restauré sur un autre appareil).
/// Partagé par l'app et le widget de l'écran de gauche : le widget lit le trousseau de l'app (même groupe de
/// trousseau, l'identifiant de l'app, déclaré dans `Widget/YCRMWidget.entitlements`).
struct KeychainStore {
    /// Quand l'élément est lisible.
    enum Access {
        /// iPhone déverrouillé (jetons).
        case whenUnlocked
        /// Après le 1er déverrouillage depuis le démarrage (réglages non secrets lus par le widget).
        case afterFirstUnlock
    }

    let service: String

    func read(_ account: String) -> String? {
        readWithStatus(account).value
    }

    /// La valeur, et le code du trousseau (`errSecInteractionNotAllowed` : iPhone verrouillé).
    func readWithStatus(_ account: String) -> (value: String?, status: OSStatus) {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return (nil, status) }
        return (String(data: data, encoding: .utf8), status)
    }

    func save(_ value: String, account: String, access: Access = .whenUnlocked) throws {
        delete(account)
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = access == .whenUnlocked
            ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Impossible d'enregistrer le jeton dans le trousseau (code \(status))." }
}

/// Éléments du trousseau que le widget lit : le jeton Pipedrive, et, recopiés par l'app à chaque lancement,
/// le sous-domaine Pipedrive et mon identifiant (le widget n'a pas accès aux réglages de l'app).
enum SharedKeychain {
    static let service = "com.yateo.ycrm"
    static let token = "pipedrive-api-token"
    static let domain = "pipedrive-company-domain"
    static let userID = "pipedrive-user-id"
}
