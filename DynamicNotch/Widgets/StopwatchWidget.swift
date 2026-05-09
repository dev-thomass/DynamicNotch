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

    @Published private(set) var running = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var timer: Timer?

    private init() {}

    var formatted: String {
        let total = max(0, elapsed)
        let m = Int(total) / 60
        let s = Int(total) % 60
        let cs = Int((total - floor(total)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    func toggle() {
        if running {
            running = false
            timer?.invalidate()
            timer = nil
        } else {
            running = true
            let base = elapsed
            let start = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
                Task { @MainActor [weak self] in
                    self?.elapsed = base + Date().timeIntervalSince(start)
                }
            }
        }
    }

    func reset() {
        running = false
        elapsed = 0
        timer?.invalidate()
        timer = nil
    }
}

struct StopwatchWidgetView: View {
    @StateObject var vm: NotchViewModel
    @StateObject private var model = StopwatchModel.shared

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 9, weight: .semibold))
                Text("Chrono")
                    .font(DS.Typography.captionSmall)
                Spacer()
            }
            .foregroundStyle(DS.Color.textTertiary)

            Text(model.formatted)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.Color.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: DS.Spacing.sm) {
                circleBtn(systemImage: "arrow.counterclockwise", role: .secondary) {
                    model.reset()
                }
                .disabled(model.elapsed == 0 && !model.running)
                .opacity(model.elapsed == 0 && !model.running ? 0.4 : 1)

                circleBtn(
                    systemImage: model.running ? "pause.fill" : "play.fill",
                    role: model.running ? .warning : .primary
                ) { model.toggle() }
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsCard()
        .dsRimLight()
    }

    @ViewBuilder
    private func circleBtn(systemImage: String, role: ButtonRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
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
            case .primary:   DS.Color.brand
            case .warning:   DS.Color.warning
            case .secondary: DS.Color.surfaceRaisedStrong
            }
        }
        var foreground: Color {
            switch self {
            case .secondary: DS.Color.textPrimary
            default:         DS.Color.textOnAccent
            }
        }
    }
}
