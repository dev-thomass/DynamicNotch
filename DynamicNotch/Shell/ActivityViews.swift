//
//  ActivityViews.swift
//  DynamicNotch
//
//  Contenu des ailes (compact) et de l'état étendu, par activité. Chaque vue
//  n'observe que SON modèle : un chrono qui tourne ne fait plus recalculer
//  toute l'encoche.
//

import EventKit
import SwiftUI

enum ActivityPlace {
    case compactLeading
    case compactTrailing
    case expanded
}

/// Ailes compactes, de part et d'autre de l'encoche physique.
struct CompactActivityView: View {
    let id: ActivityID
    let notchWidth: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        let wing = WingLayout.wingWidth(for: id)
        HStack(spacing: 0) {
            ActivitySlot(id: id, place: .compactLeading, namespace: namespace)
                .frame(width: wing - WingLayout.padding, alignment: .leading)
                .padding(.leading, WingLayout.padding)
            Spacer(minLength: notchWidth)
            ActivitySlot(id: id, place: .compactTrailing, namespace: namespace)
                .frame(width: wing - WingLayout.padding, alignment: .trailing)
                .padding(.trailing, WingLayout.padding)
        }
        .font(DS.Typography.wing)
        .foregroundStyle(DS.Color.textPrimary)
    }
}

/// État étendu : une ligne sous l'encoche (icône, titre, valeur).
struct ExpandedActivityView: View {
    let id: ActivityID
    let notchHeight: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: notchHeight)
            ActivitySlot(id: id, place: .expanded, namespace: namespace)
                .frame(height: 36)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .foregroundStyle(DS.Color.textPrimary)
    }
}

/// Barres audio animées tant que la lecture est en cours.
struct AudioBars: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0 ..< 4, id: \.self) { index in
                    Capsule()
                        .fill(DS.Color.textPrimary)
                        .frame(
                            width: 2.5,
                            height: isPlaying ? 4 + 8 * abs(sin(t * (5 + Double(index)) + Double(index) * 1.3)) : 3
                        )
                }
            }
            .frame(width: 18, height: 14)
        }
    }
}

// MARK: - Aiguillage

private struct ActivitySlot: View {
    let id: ActivityID
    let place: ActivityPlace
    let namespace: Namespace.ID

    var body: some View {
        switch id {
        case .charging, .unplugged, .lowBattery:
            BatteryActivity(id: id, place: place, namespace: namespace)
        case .pomodoroPhase:
            PomodoroActivity(place: place, namespace: namespace)
        case .stopwatch:
            StopwatchActivity(place: place)
        case .nowPlaying:
            NowPlayingActivity(place: place, namespace: namespace)
        case .calendarSoon:
            CalendarActivity(place: place)
        case let .filesAdded(count):
            ConfirmationActivity(
                place: place, systemImage: "checkmark.circle.fill", tint: DS.Color.success,
                title: count > 1 ? "\(count) fichiers ajoutés" : "1 fichier ajouté"
            )
        case .airDropSent:
            ConfirmationActivity(
                place: place, systemImage: "checkmark.circle.fill", tint: DS.Color.info,
                title: "Envoyé via AirDrop"
            )
        }
    }
}

/// Ligne standard de l'état étendu.
private struct ActivityRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let leading: Leading
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(DS.Typography.activityTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typography.activitySubtitle)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
    }
}

// MARK: - Batterie

private struct BatteryActivity: View {
    let id: ActivityID
    let place: ActivityPlace
    let namespace: Namespace.ID
    private var battery = BatteryMonitor.shared

    private var isLow: Bool {
        if case .lowBattery = id {
            return true
        }
        return false
    }

    private var tint: Color {
        if isLow {
            return DS.Color.destructive
        }
        return battery.isPluggedIn ? DS.Color.success : battery.indicativeTint
    }

    private var valueColor: Color {
        if isLow {
            return DS.Color.destructive
        }
        return battery.isPluggedIn ? DS.Color.success : DS.Color.textPrimary
    }

    private var title: String {
        switch id {
        case .charging: "En charge"
        case .unplugged: "Sur batterie"
        default: "Batterie faible"
        }
    }

    var body: some View {
        switch place {
        case .compactLeading:
            glyph(width: 22)
        case .compactTrailing:
            percent.foregroundStyle(valueColor)
        case .expanded:
            ActivityRow(title: title, subtitle: id == .charging ? battery.timeToFullText : nil) {
                glyph(width: 44)
            } trailing: {
                percent
                    .font(DS.Typography.activityValue)
                    .foregroundStyle(valueColor)
            }
        }
    }

    private func glyph(width: CGFloat) -> some View {
        BatteryGlyph(
            level: battery.level, tint: tint, isCharging: battery.isCharging, width: width,
            pulsesBolt: place == .expanded && id == .charging
        )
        .matchedGeometryEffect(id: "battery", in: namespace)
    }

    private var percent: some View {
        Text("\(battery.percent) %")
            .contentTransition(.numericText(value: Double(battery.percent)))
            .animation(DS.Motion.micro, value: battery.percent)
    }
}

// MARK: - Pomodoro

private struct PomodoroActivity: View {
    let place: ActivityPlace
    let namespace: Namespace.ID
    private var model = PomodoroModel.shared

    var body: some View {
        switch place {
        case .compactLeading:
            dot(size: 8)
        case .compactTrailing:
            remaining
        case .expanded:
            ActivityRow(title: model.phase.activityTitle, subtitle: "\(Int(model.phaseTotal / 60)) min") {
                dot(size: 14)
            } trailing: {
                remaining.font(DS.Typography.activityValue)
            }
        }
    }

    private func dot(size: CGFloat) -> some View {
        Circle()
            .fill(model.phase.tint)
            .frame(width: size, height: size)
            .matchedGeometryEffect(id: "pomodoro", in: namespace)
    }

    private var remaining: some View {
        Text(model.formatted)
            .contentTransition(.numericText(countsDown: true))
            .animation(DS.Motion.micro, value: model.formatted)
    }
}

// MARK: - Chrono

private struct StopwatchActivity: View {
    let place: ActivityPlace
    private var model = StopwatchModel.shared

    var body: some View {
        switch place {
        case .compactLeading:
            Image(systemName: "stopwatch")
        case .compactTrailing:
            time
        case .expanded:
            ActivityRow(title: "Chrono") {
                Image(systemName: "stopwatch").font(.system(size: 20, weight: .semibold))
            } trailing: {
                time.font(DS.Typography.activityValue)
            }
        }
    }

    @ViewBuilder
    private var time: some View {
        if let startedAt = model.startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                label(model.elapsed(at: context.date))
            }
        } else {
            label(model.elapsed(at: Date()))
        }
    }

    private func label(_ elapsed: TimeInterval) -> some View {
        let text = StopwatchModel.minutesSeconds(elapsed)
        return Text(text)
            .contentTransition(.numericText())
            .animation(DS.Motion.micro, value: text)
    }
}

// MARK: - Musique

private struct NowPlayingActivity: View {
    let place: ActivityPlace
    let namespace: Namespace.ID
    private var player = NowPlayingManager.shared

    var body: some View {
        switch place {
        case .compactLeading:
            artwork(size: 20)
        case .compactTrailing:
            AudioBars(isPlaying: player.isPlaying)
        case .expanded:
            ActivityRow(
                title: player.title.isEmpty ? "Lecture en cours" : player.title,
                subtitle: player.artist.isEmpty ? nil : player.artist
            ) {
                artwork(size: 36)
            } trailing: {
                AudioBars(isPlaying: player.isPlaying)
            }
        }
    }

    private func artwork(size: CGFloat) -> some View {
        Group {
            if let image = player.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    DS.Color.surfaceRaisedStrong
                    Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .semibold))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .matchedGeometryEffect(id: "artwork", in: namespace)
    }
}

// MARK: - Calendrier

private struct CalendarActivity: View {
    let place: ActivityPlace
    private var store = CalendarStore.shared

    var body: some View {
        switch place {
        case .compactLeading:
            Image(systemName: "calendar")
        case .compactTrailing:
            countdown
        case .expanded:
            ActivityRow(title: store.nextEvent?.title ?? "Événement", subtitle: "Bientôt") {
                Image(systemName: "calendar").font(.system(size: 20, weight: .semibold))
            } trailing: {
                countdown.font(DS.Typography.activityValue)
            }
        }
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minutes = store.nextEvent
                .map { max(0, Int(ceil($0.startDate.timeIntervalSince(context.date) / 60))) } ?? 0
            Text("\(minutes) min")
                .contentTransition(.numericText(countsDown: true))
                .animation(DS.Motion.micro, value: minutes)
        }
    }
}

// MARK: - Confirmations (fichiers, AirDrop)

private struct ConfirmationActivity: View {
    let place: ActivityPlace
    let systemImage: String
    let tint: Color
    let title: String

    var body: some View {
        switch place {
        case .compactLeading:
            Image(systemName: systemImage).foregroundStyle(tint)
        case .compactTrailing:
            EmptyView()
        case .expanded:
            ActivityRow(title: title) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tint)
            } trailing: {
                EmptyView()
            }
        }
    }
}
