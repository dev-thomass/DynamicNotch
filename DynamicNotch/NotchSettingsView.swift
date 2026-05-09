//
//  NotchSettingsView.swift
//  DynamicNotch
//
//  Created by 曹丁杰 on 2024/7/29.
//
//  Refactored on 2026-05-09 — split into typed sections, wired to AppSettings,
//  uses Design System tokens, fixes localized picker layout (T-35).
//

import AppKit
import LaunchAtLogin
import SwiftUI

struct NotchSettingsView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm: TrayDrop = .shared
    @StateObject var settings: AppSettings = .shared

    var body: some View {
        // Layout 3 colonnes : la section Widgets prend toute la largeur en
        // haut (concerne le contenu principal), puis 3 colonnes pour les
        // groupes thématiques. Le ScrollView garantit que tout reste
        // accessible si l'utilisateur réduit la taille de la fenêtre.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                widgetsSection

                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        appearanceSection
                        behaviorSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        displaySection
                        storageSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        pomodoroSection
                        advancedSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                versionFooter
            }
            .padding(DS.Spacing.md)
        }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: widgets

    private var widgetsSection: some View {
        sectionCard(title: "Widgets", systemImage: "rectangle.3.group") {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(0 ..< vm.widgetPages.count, id: \.self) { pageIndex in
                    widgetPageRow(pageIndex)
                }
                if vm.widgetPages.count < NotchViewModel.maxPages {
                    Button {
                        withAnimation(vm.animation) { vm.addPage() }
                    } label: {
                        Label("Ajouter une page", systemImage: "plus.circle")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func widgetPageRow(_ pageIndex: Int) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Page \(pageIndex + 1)")
                    .font(DS.Typography.captionSmall)
                    .foregroundStyle(DS.Color.textSecondary)
                if vm.widgetPages.count > 1 {
                    Button {
                        withAnimation(vm.animation) { vm.removePage(pageIndex) }
                    } label: {
                        Text("Supprimer")
                            .font(DS.Typography.captionSmall)
                            .foregroundStyle(DS.Color.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 64, alignment: .leading)

            // Widget chips: tap to toggle. Active widgets are filled with
            // their tone, inactive widgets are outlined. Horizontal scroll
            // lets us keep all options visible regardless of locale length.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(NotchViewModel.Widget.allCases) { widget in
                        widgetChip(widget, pageIndex: pageIndex)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func widgetChip(_ widget: NotchViewModel.Widget, pageIndex: Int) -> some View {
        let isActive = vm.widgetPages[pageIndex].contains(widget)
        let canAdd = isActive || vm.widgetPages[pageIndex].count < NotchViewModel.maxWidgetsPerPage

        Button {
            withAnimation(vm.animation) {
                vm.toggleWidget(widget, onPage: pageIndex)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: widget.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(widget.label)
                    .font(DS.Typography.captionSmall)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous).fill(
                    isActive ? DS.Color.brand.opacity(0.85) : DS.Color.surfaceRaised
                )
            )
            .overlay(
                Capsule(style: .continuous).strokeBorder(
                    isActive ? DS.Color.brand : DS.Color.borderDefault,
                    lineWidth: 1
                )
            )
            .foregroundStyle(isActive ? DS.Color.textOnAccent : DS.Color.textSecondary)
            .opacity(canAdd ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .help(canAdd
              ? Text(isActive ? "Retirer de la page" : "Ajouter à la page")
              : Text("Page pleine (max \(NotchViewModel.maxWidgetsPerPage) widgets)")
        )
    }

    // MARK: appearance

    private var appearanceSection: some View {
        sectionCard(title: "Apparence", systemImage: "paintbrush") {
            HStack {
                Text("Opacité de l'encoche").font(DS.Typography.caption)
                Slider(value: $settings.notchOpacity, in: 0.4 ... 1.0, step: 0.05)
                Text(String(format: "%.0f %%", settings.notchOpacity * 100))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    // MARK: behaviour

    private var behaviorSection: some View {
        sectionCard(title: "Comportement", systemImage: "gear") {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Toggle(isOn: $vm.hapticFeedback) {
                    settingLabel("Retour haptique", subtitle: "Léger tapotement quand l'encoche s'ouvre")
                }
                Toggle(isOn: $settings.popOnHoverEnabled) {
                    settingLabel("Apparition au survol", subtitle: "Anime l'encoche quand le curseur s'approche")
                }
                Toggle(isOn: $settings.alwaysVisibleWhenClosed) {
                    settingLabel("Toujours visible", subtitle: "L'encoche ne devient jamais semi-transparente")
                }
                Toggle(isOn: $settings.escClosesNotch) {
                    settingLabel("Échap pour fermer", subtitle: "La touche Esc referme l'encoche ouverte")
                }
                LaunchAtLogin.Toggle {
                    settingLabel("Lancer à l'ouverture de session", subtitle: nil)
                }
            }
        }
    }

    // MARK: display

    private var displaySection: some View {
        sectionCard(title: "Affichage", systemImage: "display") {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                // Picker écran : montre l'écran intégré, "écran principal"
                // (= celui qui a le focus système au moment de la résolution),
                // et chaque écran externe par son nom — qu'il ait une encoche
                // matérielle ou non. Sur un écran sans encoche, DynamicNotch
                // bascule automatiquement en mode "pilule".
                VStack(alignment: .leading, spacing: 2) {
                    Text("Encoche affichée sur").font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Color.textTertiary)
                    Picker("", selection: displayBinding) {
                        Text(DisplayPreference.builtInWithNotch.displayName)
                            .tag(DisplayPreference.builtInWithNotch)
                        Text(DisplayPreference.mainAtResolveTime.displayName)
                            .tag(DisplayPreference.mainAtResolveTime)
                        if !connectedExternals.isEmpty { Divider() }
                        ForEach(connectedExternals, id: \.self) { name in
                            Text(name).tag(DisplayPreference.named(name))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                if connectedExternals.isEmpty {
                    Text("Branchez un écran externe pour le voir apparaître ici.")
                        .font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(2)
                }

                Toggle(isOn: $settings.forcePillMode) {
                    settingLabel("Forcer le mode pilule",
                                 subtitle: "Ignore l'encoche matérielle et affiche une pilule arrondie")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Langue").font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Color.textTertiary)
                    Picker("", selection: $vm.selectedLanguage) {
                        ForEach(Language.allCases) { language in
                            Text(language.localized).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: pomodoro

    private var pomodoroSection: some View {
        sectionCard(title: "Pomodoro", systemImage: "brain.head.profile") {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                pomodoroStepper(
                    "Focus",
                    binding: $settings.pomodoroFocusMinutes,
                    range: 5...90,
                    suffix: "min"
                )
                pomodoroStepper(
                    "Pause courte",
                    binding: $settings.pomodoroShortBreakMinutes,
                    range: 1...30,
                    suffix: "min"
                )
                pomodoroStepper(
                    "Pause longue",
                    binding: $settings.pomodoroLongBreakMinutes,
                    range: 5...60,
                    suffix: "min"
                )
                pomodoroStepper(
                    "Cycles avant pause longue",
                    binding: $settings.pomodoroCyclesBeforeLongBreak,
                    range: 2...8,
                    suffix: nil
                )
            }
        }
    }

    @ViewBuilder
    private func pomodoroStepper(_ title: LocalizedStringKey, binding: Binding<Int>, range: ClosedRange<Int>, suffix: String?) -> some View {
        HStack {
            Text(title)
                .font(DS.Typography.captionSmall)
                .foregroundStyle(DS.Color.textSecondary)
            Spacer()
            Stepper(value: binding, in: range) {
                Text(suffix.map { "\(binding.wrappedValue) \($0)" } ?? "\(binding.wrappedValue)")
                    .font(DS.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textPrimary)
            }
            .labelsHidden()
        }
    }

    /// External-display names (no built-in). Recomputed each render so a hot-plug
    /// reflects without manual refresh.
    private var connectedExternals: [String] {
        NSScreen.screens
            .filter { !$0.isBuildinDisplay }
            .map(\.localizedName)
            .sorted()
    }

    /// Two-way binding that hides the underlying enum from the Picker —
    /// avoids needing Hashable witness gymnastics at the call site.
    private var displayBinding: Binding<DisplayPreference> {
        Binding(
            get: { settings.displayPreference },
            set: { settings.displayPreference = $0 }
        )
    }

    // MARK: storage

    private var storageSection: some View {
        sectionCard(title: "Stockage", systemImage: "tray.full") {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Text("Conserver les fichiers pendant").font(DS.Typography.caption)
                    Picker("", selection: $tvm.selectedFileStorageTime) {
                        ForEach(TrayDrop.FileStorageTime.allCases) { time in
                            Text(time.localized).tag(time)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if tvm.selectedFileStorageTime == .custom {
                    HStack {
                        TextField("", value: $tvm.customStorageTime, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Picker("", selection: $tvm.customStorageTimeUnit) {
                            ForEach(TrayDrop.CustomstorageTimeUnit.allCases) { unit in
                                Text(unit.localized).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
                DSButton("Afficher le dossier de stockage", systemImage: "folder", role: .secondary, size: .small) {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        documentsDirectory.appendingPathComponent(TrayDrop.DropItem.mainDir)
                    ])
                }
            }
        }
    }

    // MARK: advanced

    private var advancedSection: some View {
        sectionCard(title: "Avancé", systemImage: "wrench.and.screwdriver") {
            HStack {
                DSButton(
                    "Réinitialiser les réglages",
                    systemImage: "arrow.counterclockwise",
                    role: .warning,
                    size: .small
                ) {
                    confirmAndReset()
                }
            }
        }
    }

    private func confirmAndReset() {
        let title = "Réinitialiser tous les réglages ?"
        let message = "Les préférences vont être restaurées aux valeurs par défaut. Vos fichiers déposés ne seront pas affectés."
        guard NSAlert.popConfirm(title: title, message: message, confirm: "Réinitialiser", destructive: true) else { return }
        settings.notchOpacity = 1.0
        settings.popOnHoverEnabled = true
        settings.alwaysVisibleWhenClosed = false
        settings.escClosesNotch = true
        settings.displayPreference = .builtInWithNotch
        settings.forcePillMode = false
        settings.pomodoroFocusMinutes = 25
        settings.pomodoroShortBreakMinutes = 5
        settings.pomodoroLongBreakMinutes = 15
        settings.pomodoroCyclesBeforeLongBreak = 4
        vm.hapticFeedback = true
    }

    // MARK: footer

    private var versionFooter: some View {
        HStack {
            Spacer()
            Text(verbatim: "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                .font(DS.Typography.captionSmall)
                .foregroundStyle(DS.Color.textTertiary)
            Spacer()
        }
        .padding(.top, DS.Spacing.xs)
    }

    // MARK: building blocks

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Color.brand)
                Text(title)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .textCase(.uppercase)
            }
            content()
                .padding(DS.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard(radius: DS.Radius.md)
        }
    }

    @ViewBuilder
    private func settingLabel(_ title: LocalizedStringKey, subtitle: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(DS.Typography.body).foregroundStyle(DS.Color.textPrimary)
            if let subtitle {
                Text(subtitle).font(DS.Typography.captionSmall).foregroundStyle(DS.Color.textTertiary)
            }
        }
    }
}

#Preview {
    NotchSettingsView(vm: .init())
        .padding()
        .frame(width: 600, height: 320, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
