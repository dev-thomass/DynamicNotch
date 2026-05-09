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

    @State var dropTargeting: Bool = false

    /// Wings actives au moment du rendu. Recalculé à chaque tick — coût
    /// négligeable (3 booleans + 2 enums).
    private var activeWings: [WingProvider] { WingsResolver().activeProviders }

    /// Largeur additionnelle à donner à la silhouette pour englober les
    /// wings gauche + droite. 0 si rien n'est actif.
    private var wingsExtraWidth: CGFloat {
        guard vm.status == .closed, !activeWings.isEmpty else { return 0 }
        // Une wing par côté max — providers au-delà sont ignorés (V1).
        return CGFloat(min(activeWings.count, 2)) * WingsLayout.oneWingWidth
    }

    var notchSize: CGSize {
        switch vm.status {
        case .closed:
            var ans = CGSize(
                width: vm.deviceNotchRect.width - 4 + wingsExtraWidth,
                height: vm.deviceNotchRect.height - 4
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
                // Combine "is the notch resting?" with the user-tunable max
                // opacity. Quand "alwaysVisibleWhenClosed" est actif, on ignore
                // le fade vers 0.3 (notchVisible) et on garde 1 × notchOpacity.
                .opacity({
                    let resting = settings.alwaysVisibleWhenClosed ? 1 : (vm.notchVisible ? 1 : 0.3)
                    return resting * settings.notchOpacity
                }())
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
        // HUD volume / luminosité, ancré sous l'encoche.
        .overlay(alignment: .top) {
            NotchHUDView()
                .offset(y: notchSize.height + 8)
                .allowsHitTesting(false)
        }
        .animation(vm.animation, value: vm.status)
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
        .overlay(alignment: .trailing) { closedBadge }
    }

    /// Contenu des wings — affiché par-dessus la silhouette noire élargie.
    /// Les `frame` calculés sont basés sur `notchSize` qui inclut déjà
    /// `wingsExtraWidth`, donc l'alignement marche tout seul.
    @ViewBuilder
    private var wingsOverlay: some View {
        if vm.status == .closed, !activeWings.isEmpty {
            HStack(spacing: 0) {
                if activeWings.count >= 1 {
                    WingContent(provider: activeWings[0], slot: .left)
                        .padding(.leading, WingsLayout.innerPadding)
                        .frame(width: WingsLayout.oneWingWidth, alignment: .leading)
                }
                Spacer(minLength: 0)
                if activeWings.count >= 2 {
                    WingContent(provider: activeWings[1], slot: .right)
                        .padding(.trailing, WingsLayout.innerPadding)
                        .frame(width: WingsLayout.oneWingWidth, alignment: .trailing)
                }
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
