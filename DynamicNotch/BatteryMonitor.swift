//
//  BatteryMonitor.swift
//  DynamicNotch
//
//  État de la batterie, mis à jour instantanément par l'abonnement système
//  IOPSNotificationCreateRunLoopSource (plus de minuterie de 10 s).
//  `onChange` reçoit le nouvel état et les événements détectés.
//

import Combine
import IOKit.ps
import SwiftUI

@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var snapshot = PowerSnapshot(
        hasBattery: false, level: 1, isPluggedIn: true, isCharging: false, minutesToFull: nil
    )
    var onChange: ((PowerSnapshot, [PowerEvent]) -> Void)?

    private var detector = PowerEventDetector()
    private var runLoopSource: CFRunLoopSource?

    private init() {
        refresh()
        // Singleton jamais libéré : un pointeur non retenu suffit.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
    }

    // MARK: accès simplifiés

    var level: Double { snapshot.level }
    var isCharging: Bool { snapshot.isCharging }
    var isPluggedIn: Bool { snapshot.isPluggedIn }
    var hasBattery: Bool { snapshot.hasBattery }
    var percent: Int { snapshot.percent }

    /// « 87 % », avec l'espace insécable de la typographie française.
    var percentText: String { "\(percent) %" }

    /// Vert au-dessus de 50 %, jaune au-dessus de 20 %, rouge en dessous.
    var indicativeTint: Color {
        if level > 0.5 { return DS.Color.success }
        if level > 0.2 { return DS.Color.warning }
        return DS.Color.destructive
    }

    /// « Pleine dans 1 h 10 », « Pleine dans 25 min », ou `nil` si inconnu.
    var timeToFullText: String? {
        guard let minutes = snapshot.minutesToFull else { return nil }
        if minutes < 60 { return "Pleine dans \(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "Pleine dans \(minutes / 60) h" : "Pleine dans \(minutes / 60) h \(String(format: "%02d", rest))"
    }

    func refresh() {
        let next = Self.readSnapshot()
        let events = detector.process(next)
        snapshot = next
        onChange?(next, events)
    }

    private static func readSnapshot() -> PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return PowerSnapshot.parse([]) }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return PowerSnapshot.parse(descriptions)
    }
}
