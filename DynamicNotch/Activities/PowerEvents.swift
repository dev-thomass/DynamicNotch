//
//  PowerEvents.swift
//  DynamicNotch
//
//  Lecture pure de l'état d'alimentation (dictionnaires IOKit) et détection
//  des événements : branchement, débranchement, franchissement des seuils de
//  batterie faible. Aucune dépendance système : testable avec des données factices.
//

import Foundation
import IOKit.ps

struct PowerSnapshot: Equatable {
    var hasBattery: Bool
    /// 0…1
    var level: Double
    var isPluggedIn: Bool
    var isCharging: Bool
    /// `nil` quand macOS ne sait pas encore estimer.
    var minutesToFull: Int?

    var percent: Int { Int((level * 100).rounded()) }

    /// Parse les descriptions renvoyées par `IOPSGetPowerSourceDescription`.
    static func parse(_ descriptions: [[String: Any]]) -> PowerSnapshot {
        guard let battery = descriptions.first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }) else {
            // Mac de bureau : toujours sur secteur, pas de batterie.
            return PowerSnapshot(hasBattery: false, level: 1, isPluggedIn: true, isCharging: false, minutesToFull: nil)
        }
        var level = 1.0
        if let capacity = battery[kIOPSCurrentCapacityKey] as? Int,
           let maximum = battery[kIOPSMaxCapacityKey] as? Int, maximum > 0
        {
            level = min(1, Double(capacity) / Double(maximum))
        }
        let timeToFull = battery[kIOPSTimeToFullChargeKey] as? Int ?? -1
        return PowerSnapshot(
            hasBattery: true,
            level: level,
            isPluggedIn: (battery[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
            isCharging: battery[kIOPSIsChargingKey] as? Bool ?? false,
            minutesToFull: timeToFull > 0 ? timeToFull : nil
        )
    }
}

enum PowerEvent: Equatable {
    case pluggedIn
    case unplugged
    case lowBattery(percent: Int)
}

struct PowerEventDetector {
    static let thresholds = [20, 10]

    private var previous: PowerSnapshot?
    private var firedThresholds: Set<Int> = []

    mutating func process(_ snapshot: PowerSnapshot) -> [PowerEvent] {
        defer { previous = snapshot }
        guard snapshot.hasBattery else { return [] }
        let percent = snapshot.percent

        guard let previous else {
            // Au lancement : les seuils déjà franchis ne déclenchent rien.
            firedThresholds = Set(Self.thresholds.filter { percent <= $0 })
            return []
        }

        var events: [PowerEvent] = []
        if !previous.isPluggedIn, snapshot.isPluggedIn {
            events.append(.pluggedIn)
        }
        if previous.isPluggedIn, !snapshot.isPluggedIn {
            events.append(.unplugged)
            // On n'alerte que sur un franchissement pendant la décharge.
            firedThresholds = Set(Self.thresholds.filter { percent <= $0 })
            return events
        }
        if !snapshot.isPluggedIn {
            let crossed = Self.thresholds.filter { percent <= $0 && !firedThresholds.contains($0) }
            if !crossed.isEmpty {
                firedThresholds.formUnion(crossed)
                events.append(.lowBattery(percent: percent))
            }
        }
        return events
    }
}
