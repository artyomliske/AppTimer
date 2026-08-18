// AppTimer localization: keeps Russian as the development language and supplies an English bundle.
import Foundation

enum L10n {
    private final class BundleToken {}
    private static let bundle = Bundle(for: BundleToken.self)

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func text(_ key: String, languageCode: String) -> String {
        guard let path = bundle.path(forResource: languageCode, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return text(key)
        }
        return NSLocalizedString(key, bundle: localizedBundle, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }
}
