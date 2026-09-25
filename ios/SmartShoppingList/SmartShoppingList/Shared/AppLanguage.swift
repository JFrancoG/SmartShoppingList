import Foundation

enum AppLanguage {
    case english
    case spanish

    /// Uses the app's resource language, including the per-app choice in Settings.
    static var current: AppLanguage {
        AppLanguage(preferredLocalizations: Bundle.main.preferredLocalizations)
    }

    /// Speech resolves the canonical locale to an equivalent supported locale.
    var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en-US")
        case .spanish: Locale(identifier: "es-ES")
        }
    }
}

extension AppLanguage {
    init(preferredLocalizations: [String]) {
        for identifier in preferredLocalizations {
            switch Locale(identifier: identifier).language.languageCode?.identifier {
            case "en":
                self = .english
                return
            case "es":
                self = .spanish
                return
            default:
                continue
            }
        }
        self = .english
    }
}
