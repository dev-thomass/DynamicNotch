//
//  BatteryMonitor.swift
//  DynamicNotch
//
//  Singleton qui surveille l'état de la batterie via IOKit Power Source.
//  Publie 4 valeurs observables : niveau (0..1), en charge, branché, présence
//  de batterie. Refresh toutes les 10s + à chaque réveil de l'écran.
//

import Combine
import Foundation
import IOKit.ps

@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var level: Double = 1.0
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var hasBattery: Bool = false

    private var timer: Timer?

    private init() {
        refresh()
        // 10 s est un bon compromis : suffisant pour voir grimper la charge,
        // pas assez fréquent pour peser sur la batterie elle-même.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    /// Affiche le pourcentage entier formaté (ex. "87 %"). Espace insécable
    /// avant le % conformément aux règles typographiques françaises.
    var percentText: String {
        let pct = Int((level * 100).rounded())
        return "\(pct) %"
    }

    /// Couleur indicative selon le niveau de charge — vert > 50 %, jaune
    /// > 20 %, rouge en dessous. Utilisée par le wing batterie pour le
    /// remplissage de l'icône.
    var indicativeTint: Color {
        if level > 0.5 { return .green }
        if level > 0.2 { return .yellow }
        return .red
    }

    func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            hasBattery = false
            return
        }

        for source in sources {
            guard let infoRef = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue(),
                  let info = infoRef as? [String: Any]
            else { continue }

            let type = info[kIOPSTypeKey as String] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            hasBattery = true

            if let cap = info[kIOPSCurrentCapacityKey as String] as? Int,
               let max = info[kIOPSMaxCapacityKey as String] as? Int, max > 0
            {
                level = Double(cap) / Double(max)
            }
            if let state = info[kIOPSPowerSourceStateKey as String] as? String {
                isPluggedIn = (state == kIOPSACPowerValue)
            }
            if let charging = info[kIOPSIsChargingKey as String] as? Bool {
                isCharging = charging
            }
            return
        }

        // Pas de batterie interne (Mac mini, Studio, …)
        hasBattery = false
        isCharging = false
        isPluggedIn = true
    }
}

// MARK: - Color import

import SwiftUI
