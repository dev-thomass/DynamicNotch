//
//  DisplayServicesBrightnessControl.swift
//  DynamicNotch
//
//  Luminosité de l'écran intégré via le framework privé DisplayServices
//  (chargé à l'exécution). Indisponible sans écran intégré (Mac de bureau,
//  capot fermé) ou si les symboles manquent : les touches restent à macOS.
//

import AppKit

@MainActor
final class DisplayServicesBrightnessControl: BrightnessControl {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    // Nommés `getFn`/`setFn` (et non `get`/`set`) : un stockage nommé `set` en
    // tête d'une propriété calculée à corps unique est lu par le compilateur
    // comme le mot-clé d'accesseur `set { … }`, ce qui casse la compilation.
    private let getFn: GetFn?
    private let setFn: SetFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        getFn = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
        setFn = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    }

    var isAvailable: Bool { setFn != nil && read() != nil }

    var level: Double { read() ?? 0 }

    func setLevel(_ level: Double) {
        guard let setFn, let display = builtinDisplay else { return }
        _ = setFn(display, Float(min(1, max(0, level))))
    }

    private func read() -> Double? {
        guard let getFn, let display = builtinDisplay else { return nil }
        var value: Float = 0
        guard getFn(display, &value) == 0 else { return nil }
        return Double(min(1, max(0, value)))
    }

    private var builtinDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }
}
