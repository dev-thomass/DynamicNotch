//
//  StopwatchWidget.swift
//  DynamicNotch
//
//  Lightweight stopwatch — start / pause / reset. Decimal seconds for
//  legibility (mm:ss.cc).
//

import Combine
import SwiftUI

@MainActor
final class StopwatchModel: ObservableObject {
    static let shared = StopwatchModel()

    // Plus de minuterie : le temps écoulé est calculé à la demande à partir
    // de dates. Les vues qui l'affichent se rafraîchissent via TimelineView,
    // et seulement tant qu'elles sont à l'écran.
    @Published private(set) var running = false
    @Published private(set) var accumulated: TimeInterval = 0
    @Published private(set) var startedAt: Date?

    init() {}

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    var elapsed: TimeInterval {
        elapsed()
    }

    /// Vrai dès qu'il y a quelque chose à afficher (en cours ou en pause).
    var hasTime: Bool {
        running || accumulated > 0
    }

    /// mm:ss.cc, pour le widget.
    func formatted(at date: Date = Date()) -> String {
        let total = max(0, elapsed(at: date))
        let cs = Int((total - floor(total)) * 100)
        return String(format: "%02d:%02d.%02d", Int(total) / 60, Int(total) % 60, cs)
    }

    /// mm:ss, pour l'aile.
    static func minutesSeconds(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func toggle(at date: Date = Date()) {
        if let startedAt {
            accumulated += max(0, date.timeIntervalSince(startedAt))
            self.startedAt = nil
            running = false
        } else {
            startedAt = date
            running = true
        }
    }

    func reset() {
        running = false
        startedAt = nil
        accumulated = 0
    }
}

struct StopwatchWidgetView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var model = StopwatchModel.shared

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 11, weight: .semibold))
                Text("Chrono")
                    .font(DS.Typography.captionSmall)
                Spacer()
            }
            .foregroundStyle(DS.Color.textTertiary)

            TimelineView(.periodic(from: .now, by: model.running ? 1.0 / 30 : 3600)) { context in
                Text(model.formatted(at: context.date))
                    .font(DS.Typography.displayLarge)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: DS.Spacing.sm) {
                circleBtn(systemImage: "arrow.counterclockwise", role: .secondary) {
                    model.reset()
                }
                .disabled(!model.hasTime)
                .opacity(!model.hasTime ? 0.4 : 1)

                circleBtn(
                    systemImage: model.running ? "pause.fill" : "play.fill",
                    role: model.running ? .warning : .primary
                ) {
                    if !model.running {
                        vm.hapticSender.send()
                    }
                    model.toggle()
                }
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsCard()
    }

    private func circleBtn(systemImage: String, role: ButtonRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(role.background)
                .foregroundStyle(role.foreground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    enum ButtonRole {
        case primary, warning, secondary

        var background: Color {
            switch self {
            case .primary: DS.Color.brand
            case .warning: DS.Color.warning
            case .secondary: DS.Color.surfaceRaisedStrong
            }
        }

        var foreground: Color {
            switch self {
            case .secondary: DS.Color.textPrimary
            default: DS.Color.textOnAccent
            }
        }
    }
}
