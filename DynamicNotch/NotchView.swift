//
//  NotchView.swift
//  DynamicNotch
//
//  Racine SwiftUI d'une fenêtre d'encoche. La coque est UNE forme animée
//  (`NotchShellShape`) dessinée dans le canevas fixe de la fenêtre ; le
//  contenu (ailes, activité étendue, panneau) est masqué par cette même
//  forme, donc il ne déborde jamais pendant les animations.
//

import SwiftUI

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var tray = TrayDrop.shared
    @Namespace private var activityNamespace
    @State private var dropTargeting = false

    /// Le contenu arrive après la coque et part avant elle.
    private static let contentTransition: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .offset(y: -6)).animation(DS.Motion.expand.delay(0.08)),
        removal: .opacity.animation(.easeOut(duration: 0.12))
    )

    private var centerX: CGFloat { vm.geometry.notchCenterXInWindow }

    private func shape(_ m: ShellMetrics) -> NotchShellShape {
        NotchShellShape(
            centerX: centerX, bodyWidth: m.bodyWidth, bodyHeight: m.bodyHeight,
            topRadius: m.topRadius, bottomRadius: m.bottomRadius
        )
    }

    var body: some View {
        let metrics = vm.metrics
        ZStack(alignment: .topLeading) {
            dragDetector(metrics)
            shape(metrics)
                .fill(Color.black)
                .shadow(color: .black.opacity(metrics.hasShadow ? 0.35 : 0), radius: 10, y: 4)
            content
                .frame(width: metrics.bodyWidth, height: metrics.bodyHeight, alignment: .top)
                .position(x: centerX, y: metrics.bodyHeight / 2)
                .mask(shape(metrics))
            closedBadge
        }
        .frame(
            width: NotchGeometry.windowSize.width,
            height: NotchGeometry.windowSize.height,
            alignment: .topLeading
        )
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.presentation {
        case .closed, .peek:
            Color.clear
        case let .compact(id):
            CompactActivityView(id: id, notchWidth: vm.deviceNotchRect.width, namespace: activityNamespace)
                .frame(height: vm.deviceNotchRect.height)
                .id(id)
                .transition(Self.contentTransition)
        case let .expanded(id):
            ExpandedActivityView(id: id, notchHeight: vm.deviceNotchRect.height, namespace: activityNamespace)
                .id(id)
                .transition(Self.contentTransition)
        case .opened:
            openedPanel
                .transition(Self.contentTransition)
        }
    }

    private var openedPanel: some View {
        VStack(spacing: vm.spacing) {
            NotchHeaderView(vm: vm)
            NotchContentView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Le header reste collé en haut quel que soit le contenu de la page.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(vm.spacing)
    }

    /// Pastille du nombre de fichiers en attente, à droite de l'encoche fermée.
    @ViewBuilder
    private var closedBadge: some View {
        if vm.presentation == .closed, !tray.items.isEmpty {
            DSBadge(count: tray.items.count, tone: .brand)
                .accessibilityLabel(Text("\(tray.items.count) fichier(s) en attente"))
                .position(x: centerX + vm.deviceNotchRect.width / 2 + 18, y: vm.deviceNotchRect.height / 2)
                .transition(.opacity)
        }
    }

    /// Zone de dépôt autour de la coque. L'alpha non nul est nécessaire au
    /// hit-test SwiftUI ; `.position` vient en dernier pour que seule cette
    /// zone (et non toute la fenêtre) reçoive les dépôts.
    private func dragDetector(_ metrics: ShellMetrics) -> some View {
        let width = metrics.bodyWidth + vm.dropDetectorRange
        let height = metrics.bodyHeight + vm.dropDetectorRange
        return Color.black.opacity(0.001)
            .frame(width: width, height: height)
            .accessibilityLabel(Text("DynamicNotch. Glissez des fichiers ou cliquez pour ouvrir le panneau."))
            .accessibilityAddTraits(.isButton)
            .onDrop(of: [.data], isTargeted: $dropTargeting) { _ in true }
            .onChange(of: dropTargeting) { _, targeted in
                if targeted, !vm.presentation.isOpened {
                    vm.notchOpen(.drag)
                    vm.hapticSender.send()
                } else if !targeted,
                          !vm.notchOpenedRect.insetBy(dx: vm.inset, dy: vm.inset).contains(NSEvent.mouseLocation)
                {
                    vm.notchClose()
                }
            }
            .position(x: centerX, y: height / 2)
    }
}
