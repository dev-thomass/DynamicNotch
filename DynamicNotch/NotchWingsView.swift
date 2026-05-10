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

/// Catalogue des wings (extensions latérales) disponibles. Le HUD système
/// volume/luminosité n'est PAS dans cette liste — il a sa propre logique
/// d'extension verticale (vers le bas), gérée directement dans `NotchView`.
enum WingProvider: String, CaseIterable, Identifiable {
    case battery
    case stopwatch
    case pomodoro
    case calendar

    var id: String { rawValue }
}

// MARK: - Resolver

/// Calcule à chaque appel l'état actif des wings.
@MainActor
struct WingsResolver {
    private let battery: BatteryMonitor
    private let stopwatch: StopwatchModel
    private let pomodoro: PomodoroModel
    private let calendar: CalendarStore
    private let hud: HUDController
    private let settings: AppSettings

    init(
        battery: BatteryMonitor = .shared,
        stopwatch: StopwatchModel = .shared,
        pomodoro: PomodoroModel = .shared,
        calendar: CalendarStore = .shared,
        hud: HUDController = .shared,
        settings: AppSettings = .shared
    ) {
        self.battery = battery
        self.stopwatch = stopwatch
        self.pomodoro = pomodoro
        self.calendar = calendar
        self.hud = hud
        self.settings = settings
    }

    /// Liste ordonnée des providers latéraux actuellement actifs.
    /// Premier = gauche, deuxième = droite. **Le HUD système n'est PAS
    /// listé ici** — il a sa propre logique d'extension verticale (vers
    /// le bas), gérée directement dans `NotchView`.
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
        if settings.wingCalendar,
           let event = calendar.nextEvent,
           event.startDate.timeIntervalSinceNow > 0,
           event.startDate.timeIntervalSinceNow < 60 * 60
        {
            out.append(.calendar)
        }
        return out
    }

    /// `true` dès qu'au moins une wing doit être affichée.
    var hasAnyWing: Bool { !activeProviders.isEmpty }
}

// MARK: - Constants

enum WingsLayout {
    /// Largeur additionnelle ajoutée à la silhouette de l'encoche pour
    /// accueillir UNE wing latérale (gauche ou droite).
    static let oneWingWidth: CGFloat = 60

    /// Padding interne dans la wing.
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
    @StateObject private var calendar = CalendarStore.shared
    @StateObject private var hud = HUDController.shared

    var body: some View {
        switch provider {
        case .battery:   batteryContent
        case .stopwatch: stopwatchContent
        case .pomodoro:  pomodoroContent
        case .calendar:  calendarContent
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
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    // ─── Stopwatch (mm | ss) ─────────────────────────────────────────────

    @ViewBuilder
    private var stopwatchContent: some View {
        let total = max(0, Int(stopwatch.elapsed))
        let m = total / 60
        let s = total % 60
        let display = slot == .left ? String(format: "%02d", m) : String(format: "%02d", s)
        VStack(spacing: 0) {
            Text(display)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
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
                .frame(width: 6, height: 6)
                .padding(.horizontal, 2)
        case .right:
            let total = max(0, Int(pomodoro.remaining.rounded()))
            Text(String(format: "%d:%02d", total / 60, total % 60))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    // ─── Calendar (countdown vers next event < 60 min) ───────────────────

    @ViewBuilder
    private var calendarContent: some View {
        switch slot {
        case .left:
            Image(systemName: "calendar")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
        case .right:
            if let event = calendar.nextEvent {
                let mins = max(0, Int(event.startDate.timeIntervalSinceNow / 60))
                Text(mins == 0 ? "main." : "\(mins)′")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }

}

/// Barre de progression strictement monochrome : tube gris-blanc faible
/// + remplissage blanc opaque. Pas de couleur d'accent.
/// Rendu accessible (internal) car réutilisé par `NotchView` pour le HUD
/// volume/luminosité affiché dans l'extension basse de la silhouette.
struct MonochromeBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white.opacity(0.95))
                    .frame(width: max(2, CGFloat(level) * geo.size.width))
            }
        }
    }
}

// MARK: - Battery glyph

/// Petite icône batterie qui se remplit selon le niveau, avec éclair
/// SCINTILLANT quand en charge active. Blanc/teinté selon le niveau.
///
/// Refactor : utilise des paddings symétriques pour que le remplissage
/// reste pixel-aligné au centre de la coque sur tous les Retina scaling.
/// L'ancien code avec `.padding(.leading, 1.5)` seulement créait un
/// décalage visible sur les écrans externes (DPI différent).
struct BatteryGlyph: View {
    let level: Double           // 0..1
    let tint: Color
    let isCharging: Bool

    // Dimensions de l'icône — proportions ratio 2:1 (plus la pointe).
    private let bodyWidth: CGFloat  = 16
    private let bodyHeight: CGFloat = 8
    private let bumpWidth: CGFloat  = 1.5
    private let bumpHeight: CGFloat = 4
    /// Inset interne de la coque (border + air entre border et fill).
    private let inset: CGFloat = 1.5
    private let cornerRadius: CGFloat = 2

    @State private var boltOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 1) {
            // Corps (coque + remplissage + éclair)
            ZStack {
                // Coque (border)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.8)

                // Remplissage proportionnel à level, ancré à gauche.
                // Utilise un HStack avec Spacer pour garantir l'alignment
                // pixel-perfect via le système de layout SwiftUI (plus
                // robuste que des paddings hardcodés).
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: max(0, cornerRadius - inset))
                        .fill(tint)
                        .frame(width: max(0, (bodyWidth - inset * 2) * level))
                    Spacer(minLength: 0)
                }
                .padding(inset)

                // Éclair scintillant
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 5.5, weight: .black))
                        .foregroundStyle(.white)
                        .opacity(boltOpacity)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                            ) {
                                boltOpacity = 0.4
                            }
                        }
                }
            }
            .frame(width: bodyWidth, height: bodyHeight)

            // Bump du connecteur (pointe à droite)
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .frame(width: bumpWidth, height: bumpHeight)
        }
    }
}
