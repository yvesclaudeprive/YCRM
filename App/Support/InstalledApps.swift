import UIKit
import PipedriveKit

/// Apps présentes sur l'iPhone (schémas déclarés dans LSApplicationQueriesSchemes, voir project.yml).
@MainActor
enum InstalledApps {
    static func canOpen(scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static var whatsapp: Bool { canOpen(scheme: "whatsapp") }

    /// Liens OnOff reconnus sur cet iPhone (pour trouver le bon lien, non documenté par OnOff).
    static var onoffSchemes: [String] {
        ActionLinks.onoffCandidateSchemes.filter { canOpen(scheme: $0) }
    }

    static func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// Liens web d'OnOff qui ouvrent directement l'app Number quand elle est installée (liens universels).
    static let onoffUniversalLinks = [
        "https://onoff.app.link/",
        "https://onoff.app/",
        "https://www.onoff.app/",
    ]

    /// Ouvre le lien seulement si une app installée le prend en charge (jamais Safari) ; vrai si une app s'est ouverte.
    static func openInAppOnly(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
                continuation.resume(returning: opened)
            }
        }
    }

    /// Essaie d'ouvrir l'app Number (OnOff) : schémas détectés, puis liens universels.
    static func openOnOffApp() async -> Bool {
        if let scheme = onoffSchemes.first, let url = URL(string: "\(scheme)://") {
            if await openInAppOnly(url) { return true }
        }
        for link in onoffUniversalLinks {
            if let url = URL(string: link), await openInAppOnly(url) { return true }
        }
        return false
    }
}
