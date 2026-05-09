//
//  BrightnessManager.swift
//  DynamicNotch
//
//  Lit et écrit la luminosité de l'écran intégré via DisplayServices
//  (framework privé). Lit aussi via IOKit comme fallback. Le HUD utilise
//  ce singleton pour afficher la valeur courante.
//

import Combine
import CoreGraphics
import Foundation

@MainActor
final class BrightnessManager: ObservableObject {
    static let shared = BrightnessManager()

    @Published private(set) var level: Float = 0.5

    private var pollTimer: Timer?

    private init() {
        refresh()
        // Polling léger : la luminosité peut changer via curseur menubar,
        // ambient light sensor, etc. — sans listener KVO disponible côté
        // public.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        if let v = readDisplayServices() { level = v; return }
        if let v = readIOKit()           { level = v; return }
    }

    /// Définit la luminosité de l'écran intégré (0..1).
    func setBrightness(_ newValue: Float) {
        let clamped = min(1, max(0, newValue))
        if writeDisplayServices(clamped) {
            level = clamped
            return
        }
        if writeIOKit(clamped) {
            level = clamped
        }
    }

    // MARK: DisplayServices (framework privé, méthode favorisée)

    private typealias DisplayServicesGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct DSHandles {
        let get: DisplayServicesGetBrightness?
        let set: DisplayServicesSetBrightness?
    }

    private static let handles: DSHandles = {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            return .init(get: nil, set: nil)
        }
        let get = dlsym(lib, "DisplayServicesGetBrightness").map {
            unsafeBitCast($0, to: DisplayServicesGetBrightness.self)
        }
        let set = dlsym(lib, "DisplayServicesSetBrightness").map {
            unsafeBitCast($0, to: DisplayServicesSetBrightness.self)
        }
        return .init(get: get, set: set)
    }()

    private func readDisplayServices() -> Float? {
        guard let get = Self.handles.get,
              let display = builtInDisplayID()
        else { return nil }
        var v: Float = 0
        let status = get(display, &v)
        return status == 0 ? v : nil
    }

    private func writeDisplayServices(_ v: Float) -> Bool {
        guard let set = Self.handles.set,
              let display = builtInDisplayID()
        else { return false }
        return set(display, v) == 0
    }

    // MARK: IOKit fallback

    private func readIOKit() -> Float? {
        // Pour l'instant, fallback minimal — DisplayServices marche sur tous
        // les Mac modernes que cible cette app. Si on tombe ici, on log et
        // on retourne nil (le HUD gardera la dernière valeur connue).
        Log.app.notice("brightness: DisplayServices indisponible, IOKit fallback non implémenté")
        return nil
    }

    private func writeIOKit(_: Float) -> Bool {
        Log.app.notice("brightness write: DisplayServices indisponible")
        return false
    }

    // MARK: helpers

    private func builtInDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.first { CGDisplayIsBuiltin($0) == 1 } ?? displays.first
    }
}
