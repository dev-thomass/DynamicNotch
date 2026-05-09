//
//  DisplayPreference.swift
//  DynamicNotch
//
//  User-configurable rule for picking which NSScreen the notch lives on.
//  Persisted via PublishedPersist.
//

import Cocoa

enum DisplayPreference: Codable, Equatable, Hashable {

    /// Use the built-in display when it has a hardware notch (the default,
    /// preserves the historical behaviour). Falls back to `.main` otherwise.
    case builtInWithNotch

    /// Always use whichever screen macOS reports as `.main` at resolve time.
    /// Useful for users with an external display they make their primary.
    case mainAtResolveTime

    /// Pin to a specific screen by `localizedName`. If that screen is not
    /// connected, fall back to `.builtInWithNotch`.
    case named(String)

    /// Resolve this preference into a concrete `NSScreen` from the live screen list.
    /// - Returns: the chosen screen, or `nil` if none can satisfy the preference.
    func resolve() -> NSScreen? {
        switch self {
        case .builtInWithNotch:
            if let screen = NSScreen.buildin, screen.notchSize != .zero { return screen }
            return .main

        case .mainAtResolveTime:
            return .main

        case .named(let name):
            if let match = NSScreen.screens.first(where: { $0.localizedName == name }) {
                return match
            }
            // Pinned screen disappeared (closed lid, unplugged) — be graceful.
            Log.app.notice("preferred screen '\(name, privacy: .public)' not connected, falling back")
            return DisplayPreference.builtInWithNotch.resolve()
        }
    }

    // MARK: human-readable label (for the Settings picker)

    var displayName: String {
        switch self {
        case .builtInWithNotch:
            return "Écran intégré (encoche)"
        case .mainAtResolveTime:
            return "Écran principal"
        case .named(let name):
            return name
        }
    }
}
