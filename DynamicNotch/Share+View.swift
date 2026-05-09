//
//  Share+View.swift
//  DynamicNotch
//
//  Tile compact pour AirDrop / Share. Refondu pour utiliser le DS :
//  surface raised, glow brand au targeting, plus de fond ColorfulX bricolé.
//

import Pow
import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    enum ShareType {
        case airdrop
        case generic

        var imageName: String {
            switch self {
            case .airdrop: "dot.radiowaves.up.forward"
            case .generic: "square.and.arrow.up"
            }
        }

        var title: String {
            switch self {
            case .airdrop: "AirDrop"
            case .generic: "Partager"
            }
        }

        var hint: String {
            switch self {
            case .airdrop: "Glissez ou cliquez pour envoyer"
            case .generic: "Glissez ou cliquez pour partager"
            }
        }

        var service: ([URL]) -> Share {
            switch self {
            case .airdrop:
                { urls in Share(files: urls, serviceName: .sendViaAirDrop) }
            case .generic:
                { urls in Share(files: urls) }
            }
        }
    }

    @StateObject var vm: NotchViewModel
    let type: ShareType

    @State var trigger: UUID = .init()
    @State var targeting = false
    @State private var hover = false

    var body: some View {
        content
            .onDrop(of: [.data], isTargeted: $targeting) { providers in
                trigger = .init()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    vm.notchClose()
                }
                DispatchQueue.global().async { beginDrop(providers) }
                return true
            }
            .onTapGesture { handleTap() }
    }

    // MARK: tile

    private var content: some View {
        VStack(spacing: DS.Spacing.xs) {
            iconBubble
            Text(type.title)
                .font(DS.Typography.bodyEmphasis)
                .foregroundStyle(DS.Color.textPrimary)
            Text(type.hint)
                .font(DS.Typography.captionSmall)
                .foregroundStyle(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .dsShadow(targeting ? DS.Effect.glowBrand : DS.Effect.shadowSm)
        .scaleEffect(hover && !targeting ? 1.02 : 1)
        .animation(DS.Motion.fast, value: hover)
        .animation(DS.Motion.base, value: targeting)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(type.title))
        .accessibilityHint(Text(type.hint))
        .accessibilityAddTraits(.isButton)
        .changeEffect(
            .spray(origin: UnitPoint(x: 0.5, y: 0.5)) {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(DS.Color.brand)
            },
            value: trigger
        )
    }

    @ViewBuilder
    private var iconBubble: some View {
        ZStack {
            Circle()
                .fill(targeting ? DS.Color.brand : DS.Color.brand.opacity(0.18))
                .frame(width: 36, height: 36)
            Image(systemName: type.imageName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(targeting ? DS.Color.textOnAccent : DS.Color.brand)
        }
    }

    @ViewBuilder
    private var background: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(targeting ? DS.Color.brand.opacity(0.18) : DS.Color.surfaceRaised)
    }

    @ViewBuilder
    private var border: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(
                targeting ? DS.Color.brand : DS.Color.borderDefault,
                lineWidth: targeting ? 1.5 : 1
            )
    }

    // MARK: actions

    private func handleTap() {
        trigger = .init()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            vm.notchClose()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let picker = NSOpenPanel()
            picker.allowsMultipleSelection = true
            picker.canChooseDirectories = true
            picker.canChooseFiles = true
            picker.begin { response in
                if response == .OK {
                    type.service(picker.urls).begin()
                }
            }
        }
    }

    func beginDrop(_ providers: [NSItemProvider]) {
        precondition(!Thread.isMainThread)
        guard let urls = providers.interfaceConvert() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            type.service(urls).begin()
        }
    }
}
