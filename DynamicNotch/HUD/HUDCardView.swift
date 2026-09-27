//
//  HUDCardView.swift
//  DynamicNotch
//
//  Carte du HUD sous l'encoche (icône, barre, pourcentage) et mini-barre
//  réutilisée par la rangée du haut du panneau ouvert.
//

import SwiftUI

struct HUDCardView: View {
    let notchHeight: CGFloat
    /// Canal du HUD de l'encoche (`NotchViewModel.hud`).
    @ObservedObject var hud: HUDController

    var body: some View {
        let state = hud.current ?? hud.lastShown ?? HUDState(kind: .volume, level: 0)
        VStack(spacing: 0) {
            Spacer(minLength: notchHeight)
            HStack(spacing: 12) {
                Image(systemName: HUDIcon.systemImage(kind: state.kind, level: state.level, isMuted: state.isMuted))
                    .font(.system(size: 22, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30)
                HUDLevelBar(level: state.level, dimmed: state.isMuted, height: 6)
                Text("\(state.percent) %")
                    .font(DS.Typography.bodyEmphasis)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(state.percent)))
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(height: 36)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .foregroundStyle(DS.Color.textPrimary)
        .animation(DS.Motion.micro, value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.kind == .volume ? "Volume \(state.percent) %" : "Luminosité \(state.percent) %"))
    }
}

/// Rail + remplissage ; au minimum un point quand le niveau est nul.
struct HUDLevelBar: View {
    let level: Double
    let dimmed: Bool
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(Color.white.opacity(dimmed ? 0.35 : 1))
                    .frame(width: max(height, geometry.size.width * min(1, max(0, level))))
            }
        }
        .frame(height: height)
    }
}
