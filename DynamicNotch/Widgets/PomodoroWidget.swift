//
//  PomodoroWidget.swift
//  DynamicNotch
//
//  Pomodoro classique : 25 min focus → 5 min pause × 4 → 15 min pause longue.
//

import Combine
import SwiftUI

@MainActor
final class PomodoroModel: ObservableObject {
    static let shared = PomodoroModel()

    enum Phase: String, Codable {
        case idle, work, shortBreak, longBreak

        var label: String {
            switch self {
            case .idle: "Prêt"
            case .work: "Focus"
            case .shortBreak: "Pause"
            case .longBreak: "Pause longue"
            }
        }

        var tint: Color {
            switch self {
            case .idle: DS.Color.textSecondary
            case .work: DS.Color.destructive
            case .shortBreak: DS.Color.success
            case .longBreak: DS.Color.brand
            }
        }

        /// Titre de l'activité affichée à l'entrée dans la phase.
        var activityTitle: String {
            switch self {
            case .idle: "Prêt"
            case .work: "Au travail"
            case .shortBreak: "Pause"
            case .longBreak: "Pause longue"
            }
        }
    }

    /// Durées lues depuis AppSettings — `var` plutôt que `let` static pour
    /// refléter les changements en temps réel quand l'utilisateur tune ses
    /// réglages. La conversion en TimeInterval (secondes) reste centralisée ici.
    var workDuration: TimeInterval {
        TimeInterval(AppSettings.shared.pomodoroFocusMinutes * 60)
    }

    var shortBreakDuration: TimeInterval {
        TimeInterval(AppSettings.shared.pomodoroShortBreakMinutes * 60)
    }

    var longBreakDuration: TimeInterval {
        TimeInterval(AppSettings.shared.pomodoroLongBreakMinutes * 60)
    }

    var cyclesBeforeLongBreak: Int {
        AppSettings.shared.pomodoroCyclesBeforeLongBreak
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var sessionsCompleted: Int = 0
    /// Le timer tourne-t-il actuellement ? Distinct de `phase != .idle` car
    /// pendant une pause utilisateur (paused), la phase reste `.work` mais le
    /// timer est arrêté. Sans cette distinction, on ne pouvait pas reprendre
    /// après pause — bug corrigé.
    @Published private(set) var isRunning: Bool = false

    private var timer: Timer?
    private var phaseEndDate: Date?

    /// Appelé à chaque changement de phase ; `naturalEnd` vaut `false` quand
    /// l'utilisateur a passé la phase.
    var onPhaseChange: ((_ phase: Phase, _ naturalEnd: Bool) -> Void)?

    init() {}

    var formatted: String {
        let total = max(0, Int(remaining.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var phaseTotal: TimeInterval {
        switch phase {
        case .idle: workDuration
        case .work: workDuration
        case .shortBreak: shortBreakDuration
        case .longBreak: longBreakDuration
        }
    }

    var progress: Double {
        guard phaseTotal > 0, phase != .idle else { return 0 }
        return 1 - (remaining / phaseTotal)
    }

    /// Progression de la phase à `date`, continue entre deux ticks.
    func progress(at date: Date) -> Double {
        guard phaseTotal > 0, phase != .idle else { return 0 }
        let left: TimeInterval = if isRunning, let end = phaseEndDate {
            max(0, end.timeIntervalSince(date))
        } else {
            remaining
        }
        return min(1, max(0, 1 - left / phaseTotal))
    }

    /// Etat ergonomique du bouton principal — utilisé par la vue pour choisir
    /// l'icône / l'action. Sépare clairement les 3 transitions possibles
    /// (idle → work, paused → resume, running → pause) pour éviter le bug
    /// précédent où "pause" sur une session déjà pausée ne faisait rien.
    enum PrimaryAction { case start, pause, resume }

    var primaryAction: PrimaryAction {
        if phase == .idle {
            return .start
        }
        return isRunning ? .pause : .resume
    }

    // MARK: actions

    func performPrimary() {
        switch primaryAction {
        case .start: transition(to: .work)
        case .pause: pauseTimer()
        case .resume: resumeTimer()
        }
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        phase = .idle
        remaining = 0
        sessionsCompleted = 0
    }

    func skip() {
        advancePhase(naturalEnd: false)
    }

    // MARK: internal

    private func transition(to next: Phase) {
        phase = next
        switch next {
        case .idle: remaining = 0
        case .work: remaining = workDuration
        case .shortBreak: remaining = shortBreakDuration
        case .longBreak: remaining = longBreakDuration
        }
        if next != .idle {
            armTimer()
        }
    }

    private func pauseTimer() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        // Capture le temps restant figé (le tick met à jour `remaining` à
        // chaque demi-seconde déjà, donc rien à faire ici).
    }

    private func resumeTimer() {
        guard remaining > 0 else { return }
        armTimer()
    }

    private func armTimer() {
        timer?.invalidate()
        isRunning = true
        phaseEndDate = Date().addingTimeInterval(remaining)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard let end = phaseEndDate else { return }
        remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            advancePhase(naturalEnd: true)
        }
    }

    private func advancePhase(naturalEnd: Bool) {
        timer?.invalidate()
        timer = nil
        isRunning = false
        switch phase {
        case .work:
            sessionsCompleted += 1
            // max(1, …) : un réglage à 0 faisait planter le modulo.
            let next: Phase = (sessionsCompleted % max(1, cyclesBeforeLongBreak) == 0) ? .longBreak : .shortBreak
            transition(to: next)
        case .shortBreak, .longBreak:
            transition(to: .work)
        case .idle:
            return
        }
        onPhaseChange?(phase, naturalEnd)
    }
}

// MARK: - View

struct PomodoroWidgetView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var model = PomodoroModel.shared

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            header
            ringWithTime
            controls
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsCard()
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 11, weight: .semibold))
            Text(model.phase.label)
                .font(DS.Typography.captionSmall)
            Spacer()
            if model.sessionsCompleted > 0 {
                Text("\(model.sessionsCompleted)")
                    .font(DS.Typography.captionSmall)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(model.phase == .idle ? DS.Color.textTertiary : model.phase.tint)
    }

    private var ringWithTime: some View {
        ZStack {
            Circle()
                .stroke(DS.Color.borderSubtle, lineWidth: 3)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isRunning)) { context in
                Circle()
                    .trim(from: 0, to: model.progress(at: context.date))
                    .stroke(model.phase.tint, style: .init(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(timeDisplayed)
                .font(DS.Typography.title)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(DS.Motion.micro, value: timeDisplayed)
                .foregroundStyle(DS.Color.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(2)
    }

    /// Quand la session est `.idle`, on affiche la durée nominale d'un focus
    /// (25:00) au lieu de "00:00" — donne un meilleur feedback "voici ce que
    /// tu vas démarrer si tu cliques play".
    private var timeDisplayed: String {
        if model.phase == .idle {
            return String(format: "%02d:00", AppSettings.shared.pomodoroFocusMinutes)
        }
        return model.formatted
    }

    private var controls: some View {
        HStack(spacing: DS.Spacing.sm) {
            circleBtn(
                systemImage: "arrow.counterclockwise",
                label: "Réinitialiser",
                enabled: model.phase != .idle || model.sessionsCompleted > 0
            ) {
                model.reset()
            }

            circleBtn(
                systemImage: primaryIcon,
                label: primaryLabel,
                tint: primaryTint
            ) {
                if !model.isRunning {
                    vm.hapticSender.send()
                }
                model.performPrimary()
            }

            circleBtn(
                systemImage: "forward.fill",
                label: "Passer à la suite",
                enabled: model.phase != .idle
            ) {
                model.skip()
            }
        }
    }

    // MARK: derived

    private var primaryIcon: String {
        switch model.primaryAction {
        case .start, .resume: "play.fill"
        case .pause: "pause.fill"
        }
    }

    private var primaryLabel: String {
        switch model.primaryAction {
        case .start: "Démarrer le focus"
        case .pause: "Mettre en pause"
        case .resume: "Reprendre"
        }
    }

    private var primaryTint: Color {
        model.phase == .idle ? DS.Color.brand : model.phase.tint
    }

    private func circleBtn(
        systemImage: String,
        label: String,
        tint: Color = DS.Color.surfaceRaisedStrong,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(tint)
                .foregroundStyle(DS.Color.textOnAccent)
                .clipShape(Circle())
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
        .help(Text(label))
    }
}
