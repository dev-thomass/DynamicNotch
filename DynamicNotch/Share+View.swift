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

    var vm: NotchViewModel
    let type: ShareType

    @State var trigger: UUID = .init()
    @State var targeting = false
    @State private var hover = false
    /// Incrémenté à l'entrée d'un glisser seulement : le rebond ne joue pas à la sortie.
    @State private var dropBounces = 0
    private let shareActivity = ShareActivity.shared

    var body: some View {
        content
            .onDrop(of: [.data], isTargeted: $targeting) { providers in
                trigger = .init()
                vm.hapticSender.send()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    vm.notchClose()
                }
                DispatchQueue.global().async { beginDrop(providers) }
                return true
            }
            .onTapGesture { handleTap() }
            .onChange(of: targeting) { _, isTargeted in
                if isTargeted {
                    dropBounces += 1
                }
            }
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

    private var iconBubble: some View {
        ZStack {
            Circle()
                .fill(targeting ? DS.Color.brand : DS.Color.brand.opacity(0.18))
                .frame(width: 36, height: 36)
            Image(systemName: type.imageName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(targeting ? DS.Color.textOnAccent : DS.Color.brand)
                .symbolEffect(.variableColor.iterative, isActive: shareActivity.isSending)
                .symbolEffect(.bounce, value: dropBounces)
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(targeting ? DS.Color.brand
                .opacity(0.18) : (hover ? DS.Color.surfaceRaisedStrong : DS.Color.surfaceRaised))
    }

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
        // Fermeture différée : laisser la gerbe Pow jouer.
        Self.pickFilesAndSend(type, vm: vm, closeAfter: 0.2)
    }

    func beginDrop(_ providers: [NSItemProvider]) {
        precondition(!Thread.isMainThread)
        Self.convertAndSend(providers, type: type, after: 0.4)
    }
}

extension ShareView {
    /// Ferme l'encoche (après `closeAfter` secondes), puis ouvre le sélecteur
    /// de fichiers 0,25 s plus tard et envoie avec `type`.
    static func pickFilesAndSend(_ type: ShareType, vm: NotchViewModel, closeAfter: TimeInterval = 0) {
        if closeAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + closeAfter) {
                MainActor.assumeIsolated { vm.notchClose() }
            }
        } else {
            vm.notchClose()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + closeAfter + 0.25) {
            MainActor.assumeIsolated {
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
    }

    /// Ferme l'encoche, puis envoie les fichiers déposés avec `type`.
    static func sendDropped(_ providers: [NSItemProvider], type: ShareType, vm: NotchViewModel) {
        vm.notchClose()
        DispatchQueue.global().async {
            convertAndSend(providers, type: type, after: 0.25)
        }
    }

    /// Conversion (hors thread principal) puis envoi (thread principal, après `delay`).
    private static func convertAndSend(_ providers: [NSItemProvider], type: ShareType, after delay: TimeInterval) {
        precondition(!Thread.isMainThread)
        guard let urls = providers.interfaceConvert() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                type.service(urls).begin()
            }
        }
    }
}
