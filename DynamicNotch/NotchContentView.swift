//
//  NotchContentView.swift
//  DynamicNotch
//
//  Renders the body of the opened notch panel based on `vm.contentType`.
//  In `.normal`, hosts the widget grid + page indicator; widgets are
//  resolved via the `Widget` enum and `widgetView(for:)`.
//

import SwiftUI
import UniformTypeIdentifiers

struct NotchContentView: View {
    @StateObject var vm: NotchViewModel

    /// Hauteur STRICTE de chaque tuile widget — explicitement appliquée à
    /// chacune via `.frame(height:)` pour garantir l'uniformité visuelle.
    ///
    /// Calcul : panel(180) − padding outer(32) − header(22) − vstack
    /// spacing(16) = 110 pt.
    ///
    /// La navigation entre pages est maintenant dans le header (chevrons
    /// ‹ X/Y ›), donc on n'a plus besoin de réserver de la place en bas
    /// pour des dots — tout l'espace inférieur est utilisé par les tuiles.
    private static let widgetTileHeight: CGFloat = 110

    var body: some View {
        ZStack {
            switch vm.contentType {
            case .normal:
                normalContent
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            case .menu:
                NotchMenuView(vm: vm)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            case .settings:
                NotchSettingsView(vm: vm)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(vm.animation, value: vm.contentType)
    }

    // MARK: normal content (widget pages)

    @ViewBuilder
    private var normalContent: some View {
        // Plus de pageSelector ici — la navigation entre pages se fait via
        // les chevrons ‹  X/Y  › dans le header (DSNotchHeader). Tout
        // l'espace dispo est utilisé par les tuiles widgets.
        widgetRow
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var widgetRow: some View {
        if vm.currentWidgets.isEmpty {
            emptyState
                .frame(height: Self.widgetTileHeight)
        } else {
            HStack(spacing: vm.spacing) {
                ForEach(vm.currentWidgets) { widget in
                    widgetView(for: widget)
                        // Largeur flexible (répartie entre widgets) +
                        // hauteur STRICTE identique pour toutes les tuiles.
                        // Pas de .clipped() : la hauteur (94pt) est large
                        // pour tous les widgets, donc rien ne déborde et
                        // les coins arrondis du dsCard restent visibles.
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.widgetTileHeight)
                }
            }
            .id(vm.currentPage) // forces a clean transition between pages
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                removal: .opacity
            ))
            .animation(vm.animation, value: vm.currentPage)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("Cette page est vide — ajoutez des widgets dans Réglages.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: routing — widget enum → SwiftUI view

    @ViewBuilder
    private func widgetView(for widget: NotchViewModel.Widget) -> some View {
        switch widget {
        case .airdrop:
            ShareView(vm: vm, type: .airdrop)
        case .files:
            TrayView(vm: vm)
        case .notes:
            NoteView(vm: vm)
        case .stopwatch:
            StopwatchWidgetView(vm: vm)
        case .pomodoro:
            PomodoroWidgetView(vm: vm)
        case .nowPlaying:
            NowPlayingWidgetView(vm: vm)
        case .calendar:
            CalendarWidgetView(vm: vm)
        }
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 160, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
