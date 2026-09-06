import Foundation

/// Tiny localization helper.
///
/// Two things it has to get right. First, `Bundle.module` is required for a
/// SwiftPM target: without it the keys aren't found and the raw key shows up
/// on screen. Second, the language picked in settings has to actually win over
/// the system language — `Bundle.module` alone always follows macOS, so a user
/// on an English Mac who picked "Русский" kept seeing English. `language` is
/// what makes that choice real; `ConfigStore` sets it whenever the config is
/// read or changed, and views pick it up on their next redraw.
enum L {
    nonisolated(unsafe) static var language: AppLanguage = .system {
        didSet { if oldValue != language { cached = nil } }
    }

    nonisolated(unsafe) private static var cached: Bundle?

    /// The bundle strings come from: the `.lproj` for the chosen language, or
    /// the module itself when following the system. A missing `.lproj` falls
    /// back to the module rather than showing bare keys.
    private static var bundle: Bundle {
        if let cached { return cached }
        let resolved: Bundle
        switch language {
        case .system:
            resolved = .module
        case .en, .ru:
            resolved = Bundle.module.path(forResource: language.rawValue, ofType: "lproj")
                .flatMap(Bundle.init(path:)) ?? .module
        }
        cached = resolved
        return resolved
    }

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), arguments: args)
    }
}
