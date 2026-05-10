//
//  NotchView.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI

struct NotchView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared
    @StateObject var settings = AppSettings.shared

    // Modèles observés pour faire re-render les wings quand leur état change.
    // Sans ces @StateObject, `WingsResolver()` retournerait des données
    // périmées et la silhouette ne saurait pas qu'il faut s'élargir.
    @StateObject private var battery = BatteryMonitor.shared
    @StateObject private var stopwatch = StopwatchModel.shared
    @StateObject private var pomodoro = PomodoroModel.shared
    @StateObject private var hud = HUDController.shared
    @StateObject private var calStore = CalendarStore.shared

    @State var dropTargeting: Bool = false

    /// Wings actives (latérales) au moment du rendu.
    private var activeWings: [WingProvider] { WingsResolver().activeProviders }

    /// `true` quand le HUD volume/luminosité doit être affiché.
    /// Le HUD est traité séparément des wings car il étend la silhouette
    /// **vers le bas** (en hauteur), pas latéralement.
    private var hudActive: Bool {
        vm.status == .closed && hud.current != nil && settings.wingsEnabled
    }

    /// Hauteur additionnelle de l'extension HUD (vers le bas). 24 pt
    /// suffisent pour un compact icône + barre fine.
    private static let hudExtraHeight: CGFloat = 24

    /// Provider unique qui occupe les wings gauche + droite à la fois.
    /// Première entrée de `activeWings`, ou nil si aucun. L'utilisateur
    /// décide la priorité en désactivant les wings qu'il ne veut pas
    /// voir gagner — par défaut l'ordre est : battery > stopwatch >
    /// pomodoro > calendar (ordre de l'enum WingProvider).
    private var primaryWing: WingProvider? {
        guard vm.status == .closed else { return nil }
        return activeWings.first
    }

    /// Largeur additionnelle à donner à la silhouette pour englober le
    /// wing gauche + droite (le provider primaire occupe les deux). 0 si
    /// aucun wing actif.
    private var wingsExtraWidth: CGFloat {
        primaryWing == nil ? 0 : 2 * WingsLayout.oneWingWidth
    }

    /// Hauteur additionnelle pour l'extension verticale du HUD.
    private var hudExtraHeight: CGFloat {
        hudActive ? Self.hudExtraHeight : 0
    }

    var notchSize: CGSize {
        switch vm.status {
        case .closed:
            var ans = CGSize(
                width: vm.deviceNotchRect.width - 4 + wingsExtraWidth,
                height: vm.deviceNotchRect.height - 4 + hudExtraHeight
            )
            if ans.width < 0 { ans.width = 0 }
            if ans.height < 0 { ans.height = 0 }
            return ans
        case .opened:
            return vm.notchOpenedSize
        case .popping:
            return .init(
                width: vm.deviceNotchRect.width,
                height: vm.deviceNotchRect.height + 4
            )
        }
    }

    var notchCornerRadius: CGFloat {
        switch vm.status {
        case .closed:
            // On Macs without a hardware notch, render the closed shell as a
            // proper pill (radius = half the height) instead of the small
            // 8-pt rect that read like a generic floating tab.
            hasHardwareNotch ? 8 : (notchSize.height / 2)
        case .opened:
            32
        case .popping:
            hasHardwareNotch ? 10 : (notchSize.height / 2)
        }
    }

    /// `true` when the host display has a real hardware notch ET que
    /// l'utilisateur n'a pas forcé le mode pilule.
    private var hasHardwareNotch: Bool {
        if settings.forcePillMode { return false }
        // The window-controller normalises a missing notch to width=150,h=28.
        // A real Mac notch is wider (≥160 on M-series). Width threshold
        // matches the simulated value exactly.
        return vm.deviceNotchRect.width > 150
    }

    var body: some View {
        ZStack(alignment: .top) {
            notch
                .zIndex(0)
                .disabled(true)
                // L'encoche est TOUJOURS pleinement visible — la fade à 0.3
                // au repos donnait des comportements incohérents (HUD
                // fantomatique, wings semi-transparentes selon l'écran).
                // Si l'utilisateur veut une encoche plus discrète au repos,
                // il y a le slider "Opacité de l'encoche" dans Réglages →
                // Apparence (multiplicateur global, persistent).
                .opacity(settings.notchOpacity)
            Group {
                if vm.status == .opened {
                    VStack(spacing: vm.spacing) {
                        NotchHeaderView(vm: vm)
                        NotchContentView(vm: vm)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // ⬇ Force la VStack à OCCUPER TOUT le frame parent.
                    // Sans ça, quand le contenu intrinsèque (somme header +
                    // widgets) est plus petit que le frame fixe (160 pt), la
                    // VStack se rend à sa taille naturelle et se trouve
                    // CENTRÉE verticalement → le header descend, et entre
                    // pages avec contenus différents le header semble
                    // « monter ». Le maxHeight: .infinity oblige la VStack
                    // à étirer son enfant flexible (ContentView) pour
                    // remplir, donc le header reste collé en haut.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(vm.spacing)
                    // Frame outer EXACT + alignment .top : fixe la taille du
                    // panneau et garantit qu'il est toujours collé au bord
                    // haut de son conteneur (pas centré).
                    .frame(
                        width: vm.notchOpenedSize.width,
                        height: vm.notchOpenedSize.height,
                        alignment: .top
                    )
                    .zIndex(1)
                }
            }
            .transition(
                .scale.combined(
                    with: .opacity
                ).combined(
                    with: .offset(y: -vm.notchOpenedSize.height / 2)
                ).animation(vm.animation)
            )
        }
        .background(dragDetector)
        // Le HUD volume/luminosité n'est PLUS rendu en bulle séparée — il
        // est désormais intégré comme une "wing prioritaire" à l'intérieur
        // de la silhouette de l'encoche (voir `NotchWingsView` +
        // `WingsResolver`). Plus sobre, plus cohérent visuellement.
        .animation(vm.animation, value: vm.status)
        // Anime l'élargissement de la silhouette quand un wing s'active /
        // se désactive (charge branchée, chrono lancé, …). Spring identique
        // à l'ouverture de l'encoche pour cohérence visuelle.
        .animation(vm.animation, value: notchSize.width)
        // Idem pour l'extension VERTICALE (HUD volume/luminosité — descend
        // par le bas).
        .animation(vm.animation, value: notchSize.height)
        // The opened panel resizes when the user enters Settings (large
        // form) or Menu (compact tile row). Animate the size change with
        // the same spring as the open/close transition for visual cohesion.
        .animation(vm.animation, value: vm.contentType)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var notch: some View {
        Group {
            if hasHardwareNotch {
                // Signature shape: rectangular body with concave outer corners
                // that meet the screen bezel. Only meaningful on real notches.
                Rectangle()
                    .foregroundStyle(.black)
                    .mask(notchBackgroundMaskGroup)
                    .frame(
                        width: notchSize.width + notchCornerRadius * 2,
                        height: notchSize.height
                    )
            } else {
                // Plain pill — looks intentional on bezel-only displays instead
                // of a tear/cutout that reads as a graphics glitch.
                RoundedRectangle(cornerRadius: notchCornerRadius, style: .continuous)
                    .foregroundStyle(.black)
                    .frame(
                        width: notchSize.width,
                        height: notchSize.height
                    )
            }
        }
        .shadow(
            color: .black.opacity(([.opened, .popping].contains(vm.status)) ? 1 : 0),
            radius: 16
        )
        .overlay { wingsOverlay }
        .overlay(alignment: .bottom) { hudOverlay }
        .overlay(alignment: .trailing) { closedBadge }
    }

    /// Contenu du HUD volume / luminosité — affiché DANS la zone basse de
    /// la silhouette (qui s'est étendue de `hudExtraHeight` vers le bas).
    /// Strictement monochrome blanc, pas de couleur.
    @ViewBuilder
    private var hudOverlay: some View {
        if hudActive, let kind = hud.current {
            HStack(spacing: 6) {
                Image(systemName: hudIcon(kind))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                MonochromeBar(level: hudLevel(kind))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            // Zone du bas — la hauteur correspond exactement à
            // `hudExtraHeight`. Centré verticalement dans ce slot.
            .frame(height: Self.hudExtraHeight)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
            .transition(.opacity)
        }
    }

    private func hudIcon(_ kind: HUDController.HUDKind) -> String {
        switch kind {
        case .volume(_, let muted): muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness:           "sun.max.fill"
        }
    }

    private func hudLevel(_ kind: HUDController.HUDKind) -> Float {
        switch kind {
        case .volume(let l, _): l
        case .brightness(let l): l
        }
    }

    /// Contenu des wings — UN seul provider occupe les deux slots (gauche
    /// = icône / pastille, droite = valeur / texte). Quand plusieurs
    /// providers sont éligibles, c'est le premier dans l'ordre `activeWings`
    /// qui gagne (l'utilisateur peut désactiver les autres dans Settings).
    @ViewBuilder
    private var wingsOverlay: some View {
        if let provider = primaryWing {
            HStack(spacing: 0) {
                WingContent(provider: provider, slot: .left)
                    .padding(.leading, WingsLayout.innerPadding)
                    .frame(width: WingsLayout.oneWingWidth, alignment: .leading)
                Spacer(minLength: 0)
                WingContent(provider: provider, slot: .right)
                    .padding(.trailing, WingsLayout.innerPadding)
                    .frame(width: WingsLayout.oneWingWidth, alignment: .trailing)
            }
            .frame(width: notchSize.width, height: notchSize.height)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    /// Pill-shaped count badge that hugs the right side of the closed notch
    /// so a returning user knows there are pending tray items at a glance.
    /// Hidden in opened/popping states (the panel itself shows the items).
    @ViewBuilder
    private var closedBadge: some View {
        if vm.status == .closed, tvm.items.count > 0 {
            DSBadge(count: tvm.items.count, tone: .brand)
                .offset(x: 18, y: 0) // sits just outside the notch silhouette
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text("\(tvm.items.count) fichier(s) en attente"))
        }
    }

    var notchBackgroundMaskGroup: some View {
        Rectangle()
            .foregroundStyle(.black)
            .frame(
                width: notchSize.width,
                height: notchSize.height
            )
            .clipShape(.rect(
                bottomLeadingRadius: notchCornerRadius,
                bottomTrailingRadius: notchCornerRadius
            ))
            .overlay {
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .frame(width: notchCornerRadius, height: notchCornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topTrailingRadius: notchCornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: notchCornerRadius + vm.spacing,
                            height: notchCornerRadius + vm.spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -notchCornerRadius - vm.spacing + 0.5, y: -0.5)
            }
            .overlay {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: notchCornerRadius, height: notchCornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topLeadingRadius: notchCornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: notchCornerRadius + vm.spacing,
                            height: notchCornerRadius + vm.spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: notchCornerRadius + vm.spacing - 0.5, y: -0.5)
            }
    }

    @ViewBuilder
    var dragDetector: some View {
        // SwiftUI requires a non-zero alpha for hit-testing on a Color, so we
        // use 0.001 (the smallest non-zero value that still registers).
        RoundedRectangle(cornerRadius: notchCornerRadius)
            .foregroundStyle(Color.black.opacity(0.001))
            .contentShape(Rectangle())
            .frame(width: notchSize.width + vm.dropDetectorRange, height: notchSize.height + vm.dropDetectorRange)
            .accessibilityLabel(Text("DynamicNotch. Glissez des fichiers ou cliquez pour ouvrir le panneau."))
            .accessibilityAddTraits(.isButton)
            .onDrop(of: [.data], isTargeted: $dropTargeting) { _ in true }
            .onChange(of: dropTargeting) { isTargeted in
                if isTargeted, vm.status == .closed {
                    // Open the notch when a file is dragged over it
                    vm.notchOpen(.drag)
                    vm.hapticSender.send()
                } else if !isTargeted {
                    // Close the notch when the dragged item leaves the area
                    let mouseLocation: NSPoint = NSEvent.mouseLocation
                    if !vm.notchOpenedRect.insetBy(dx: vm.inset, dy: vm.inset).contains(mouseLocation) {
                        vm.notchClose()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
