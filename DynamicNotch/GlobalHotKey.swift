//
//  GlobalHotKey.swift
//  DynamicNotch
//
//  Raccourci clavier global via Carbon (RegisterEventHotKey) : fonctionne
//  depuis n'importe quelle app, sans autorisation d'accessibilité.
//

import Carbon.HIToolbox

/// Combinaison de touches au format Carbon.
struct HotKeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    /// Libellé affiché dans les réglages.
    let symbols: String

    /// ⌃⌥N : ouvre ou ferme l'encoche.
    static let toggleNotch = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(controlKey | optionKey),
        symbols: "⌃⌥N"
    )
}

@MainActor
final class GlobalHotKey {
    private let combo: HotKeyCombo
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var isRegistered: Bool {
        hotKeyRef != nil
    }

    init(combo: HotKeyCombo, action: @escaping @MainActor () -> Void) {
        self.combo = combo
        self.action = action
    }

    /// Enregistre le raccourci ; `false` si une autre app le détient déjà.
    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x444E_4F54), id: 1) // "DNOT"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Log.app.error("global hotkey \(self.combo.symbols, privacy: .public) unavailable (\(status))")
            return false
        }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // L'instance vit aussi longtemps que l'app (tenue par l'AppDelegate).
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, context, &handlerRef)
    }
}
