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
    var vm: NotchViewModel
    private let tray = TrayDrop.shared
    @Namespace private var activityNamespace
    @State private var dropTargeting = false

    private var centerX: CGFloat {
        vm.geometry.notchCenterXInWindow
    }

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
                .transition(.emerge)
        case let .expanded(id):
            ExpandedActivityView(id: id, notchHeight: vm.deviceNotchRect.height, namespace: activityNamespace)
                .id(id)
                .transition(.emerge)
        case .opened:
            openedPanel
                .transition(.emerge)
        }
    }

    private var openedPanel: some View {
        VStack(spacing: 0) {
            NotchTopRow(vm: vm)
            NotchContentView(vm: vm)
                .padding(.horizontal, vm.spacing)
                .padding(.top, 8)
                .padding(.bottom, vm.spacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Pastille du nombre de fichiers en attente, à droite de la coque au
    /// repos (encoche nue ou ailes) ; masquée dans les autres états.
    @ViewBuilder
    private var closedBadge: some View {
        if showsBadge, !tray.items.isEmpty {
            DSBadge(count: tray.items.count, tone: .brand)
                .accessibilityLabel(Text("\(tray.items.count) fichier(s) en attente"))
                .position(x: centerX + vm.metrics.bodyWidth / 2 + 18, y: vm.deviceNotchRect.height / 2)
                .transition(.opacity)
        }
    }

    private var showsBadge: Bool {
        switch vm.presentation {
        case .closed, .compact: true
        case .peek, .expanded, .opened: false
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
