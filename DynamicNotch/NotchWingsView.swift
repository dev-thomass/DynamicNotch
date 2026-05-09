//
//  NotchWingsView.swift
//  DynamicNotch
//
//  Système d'« ailes » (wings) — extensions latérales de l'encoche fermée
//  qui affichent en permanence des informations contextuelles : niveau de
//  batterie en charge, chronomètre actif, pomodoro en cours, etc.
//
//  Architecture :
//   - `WingProvider` enum : énumère les producteurs possibles (battery,
//     stopwatch, pomodoro, …) avec leur priorité et leur logique d'activité.
//   - `WingsResolver` : à chaque rendu, calcule quel provider occupe la
//     wing gauche et quel provider occupe la wing droite, en fonction des
//     toggles utilisateur et de l'état des modèles.
//   - `NotchWingsView` : la vue rendue à gauche / à droite de l'encoche.
//
//  Quand au moins une wing est active, `NotchView` étend horizontalement
//  la silhouette noire pour englober les wings et donner l'illusion d'une
//  pilule continue qui sort de l'encoche.
//

import SwiftUI

// MARK: - Provider

/// Catalogue des wings disponibles. L'ordre des cas définit la priorité
/// quand plusieurs providers veulent la même slot (le premier déclaré gagne).
enum WingProvider: String, CaseIterable, Identifiable {
    case battery
    case stopwatch
    case pomodoro

    var id: String { rawValue }
}

// MARK: - Resolver

/// Calcule à chaque appel l'état actif des wings.
@MainActor
struct WingsResolver {
    private let battery: BatteryMonitor
    private let stopwatch: StopwatchModel
    private let pomodoro: PomodoroModel
    private let settings: AppSettings

    init(
        battery: BatteryMonitor = .shared,
        stopwatch: StopwatchModel = .shared,
        pomodoro: PomodoroModel = .shared,
        settings: AppSettings = .shared
    ) {
        self.battery = battery
        self.stopwatch = stopwatch
        self.pomodoro = pomodoro
        self.settings = settings
    }

    /// Liste ordonnée des providers actuellement actifs (et autorisés par
    /// les réglages utilisateur). Premier = gauche, deuxième = droite.
    var activeProviders: [WingProvider] {
        guard settings.wingsEnabled else { return [] }
        var out: [WingProvider] = []
        if settings.wingBattery, battery.hasBattery, battery.isPluggedIn {
            out.append(.battery)
        }
        if settings.wingStopwatch, stopwatch.running || stopwatch.elapsed > 0 {
            out.append(.stopwatch)
        }
        if settings.wingPomodoro, pomodoro.phase != .idle {
            out.append(.pomodoro)
        }
        return out
    }

    /// `true` dès qu'au moins une wing doit être affichée.
    var hasAnyWing: Bool { !activeProviders.isEmpty }
}

// MARK: - Constants

enum WingsLayout {
    /// Largeur additionnelle ajoutée à la silhouette de l'encoche pour
    /// accueillir UNE wing (gauche ou droite). Calibrée pour pouvoir
    /// afficher confortablement « 100 % » ou « 25:43 ».
    static let oneWingWidth: CGFloat = 60

    /// Padding interne dans la wing (entre le contenu et le bord de la
    /// silhouette).
    static let innerPadding: CGFloat = 8
}

// MARK: - Provider views

/// Vue concrète à afficher pour un provider donné, dans une slot donnée.
@MainActor
struct WingContent: View {
    let provider: WingProvider
    let slot: WingSlot

    enum WingSlot { case left, right }

    @StateObject private var battery = BatteryMonitor.shared
    @StateObject private var stopwatch = StopwatchModel.shared
    @StateObject private var pomodoro = PomodoroModel.shared

    var body: some View {
        switch provider {
        case .battery:   batteryContent
        case .stopwatch: stopwatchContent
        case .pomodoro:  pomodoroContent
        }
    }

    // ─── Battery ─────────────────────────────────────────────────────────

    @ViewBuilder
    private var batteryContent: some View {
        switch slot {
        case .left:
            BatteryGlyph(level: battery.level, tint: battery.indicativeTint, isCharging: battery.isCharging)
        case .right:
            Text(battery.percentText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                // Pulse subtil quand en charge active — confirme visuellement
                // que la batterie monte.
                .opacity(battery.isCharging ? pulseOpacity : 1.0)
                .animation(
                    battery.isCharging
                        ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                        : .default,
                    value: battery.isCharging
                )
        }
    }

    @State private var pulseOpacity: Double = 0.65

    // ─── Stopwatch (mm | ss) ─────────────────────────────────────────────

    @ViewBuilder
    private var stopwatchContent: some View {
        let total = max(0, Int(stopwatch.elapsed))
        let m = total / 60
        let s = total % 60
        let display = String(format: slot == .left ? "%02d" : "%02d", slot == .left ? m : s)
        let label   = slot == .left ? "min" : "sec"
        VStack(spacing: 0) {
            Text(display)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .offset(y: -1)
        }
    }

    // ─── Pomodoro (temps restant) ────────────────────────────────────────

    @ViewBuilder
    private var pomodoroContent: some View {
        switch slot {
        case .left:
            // Petite pastille colorée selon la phase
            Circle()
                .fill(pomodoro.phase.tint)
                .frame(width: 8, height: 8)
                .padding(.horizontal, 2)
        case .right:
            let total = max(0, Int(pomodoro.remaining.rounded()))
            Text(String(format: "%d:%02d", total / 60, total % 60))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Battery glyph

/// Petite icône batterie qui se remplit selon le niveau, avec éclair quand
/// en charge active. Blanc/teinté selon le niveau (vert > 50 %, jaune > 20 %,
/// rouge sinon).
struct BatteryGlyph: View {
    let level: Double           // 0..1
    let tint: Color
    let isCharging: Bool

    private let bodySize = CGSize(width: 22, height: 11)
    private let bumpSize = CGSize(width: 2, height: 5)

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                // Coque vide
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                // Remplissage proportionnel
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: max(0, (bodySize.width - 4) * level), height: bodySize.height - 4)
                    .padding(.leading, 2)
                // Éclair en charge
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: bodySize.width, height: bodySize.height)
                }
            }
            .frame(width: bodySize.width, height: bodySize.height)
            // Bump du connecteur
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .frame(width: bumpSize.width, height: bumpSize.height)
        }
    }
}
