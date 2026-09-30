//
//  AppDelegate.swift
//  DynamicNotch
//
//  Created by 秋星桥 on 2024/7/7.
//

import AppKit
import Cocoa
import Combine
import LaunchAtLogin

class AppDelegate: NSObject, NSApplicationDelegate {
    var isFirstOpen = true
    /// Tableau de tous les controllers actifs (un par écran quand
    /// `showOnAllScreens` est ON, sinon un seul). Le 1er reste accessible
    /// via `mainWindowController` pour la compat (wake-up, etc.).
    var windowControllers: [NotchWindowController] = []
    var mainWindowController: NotchWindowController? { windowControllers.first }
    private var settingsObservers: Set<AnyCancellable> = []
    /// Configuration d'écrans des fenêtres actuelles : on ne reconstruit que si elle change.
    private var lastLayout: WindowLayout?

    private struct WindowLayout: Equatable {
        let screens: [ScreenDescriptor]
        let forcePill: Bool

        init(screens: [ScreenDescriptor], forcePill: Bool) {
            // La hauteur de barre des menus ne sert qu'aux écrans sans encoche
            // (hauteur de la pilule) : sous une encoche, elle varie avec le
            // plein écran sans changer la géométrie, on l'ignore.
            self.screens = screens.map { screen in
                guard screen.safeAreaTop > 0 else { return screen }
                var normalized = screen
                normalized.menuBarHeight = 0
                return normalized
            }
            self.forcePill = forcePill
        }
    }

    /// Re-read each time we need it (was cached at launch and never refreshed).
    /// Cheap call, no need to memoize.
    var isLaunchedAtLogin: Bool { LaunchAtLogin.wasLaunchedAtLogin }

    func applicationDidFinishLaunching(_: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // A second launch attempt posts this distributed notification so the
        // live instance can surface the notch instead of silently doing nothing.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleWakeUpFromOtherInstance),
            name: SingleInstance.wakeUpNotification,
            object: nil
        )

        NSApp.setActivationPolicy(.accessory)

        // Menu Edit invisible mais nécessaire pour que Cmd+V/C/X/A
        // soient routés vers le first responder (TextEditor de la note).
        // Sans menubar même invisible, macOS ignore ces shortcuts pour
        // les apps `.accessory`.
        installEditMenu()

        _ = EventMonitors.shared
        // Sources d'activités (batterie, Pomodoro, chrono, plateau, AirDrop…).
        ActivityWiring.shared.install()
        // Mises à jour automatiques (no-op sur une build locale sans clé).
        Updater.shared.start()

        // Rebuild the windows when the user picks a different display
        // OU bascule "afficher sur tous les écrans".
        Publishers.CombineLatest3(
            AppSettings.shared.$displayPreference.removeDuplicates(),
            AppSettings.shared.$showOnAllScreens.removeDuplicates(),
            AppSettings.shared.$forcePillMode.removeDuplicates()
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            Log.app.info("display setting changed, rebuilding windows")
            self?.rebuildApplicationWindows(force: true)
        }
        .store(in: &settingsObservers)

        rebuildApplicationWindows(force: true)

        #if DEBUG
            ActivitySimulator.handleLaunchArguments()
        #endif
    }

    func applicationWillTerminate(_: Notification) {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func findScreenFitsOurNeeds() -> NSScreen? {
        // Honor the user's explicit display preference. If it can't be satisfied
        // (preferred screen unplugged, etc.) the preference's own resolve()
        // logic falls back gracefully to the built-in display, then to .main.
        AppSettings.shared.displayPreference.resolve()
    }

    @objc func screenParametersChanged() {
        rebuildApplicationWindows(force: false)
    }

    /// Reconstruit les fenêtres si la configuration d'écrans a changé (ou si `force`).
    /// `didChangeScreenParametersNotification` arrive souvent sans changement réel :
    /// reconstruire à chaque fois provoquait un flash et perdait l'état.
    func rebuildApplicationWindows(force: Bool) {
        let screens: [NSScreen]
        if AppSettings.shared.showOnAllScreens {
            screens = NSScreen.screens
        } else if let one = findScreenFitsOurNeeds() {
            screens = [one]
        } else {
            screens = []
        }
        let forcePill = AppSettings.shared.forcePillMode
        let layout = WindowLayout(screens: screens.map { ScreenDescriptor($0) }, forcePill: forcePill)
        guard force || layout != lastLayout else { return }
        lastLayout = layout
        defer { isFirstOpen = false }

        windowControllers.forEach { $0.destroy() }
        windowControllers.removeAll()

        let shouldOpen = isFirstOpen && !isLaunchedAtLogin
        for (index, screen) in screens.enumerated() {
            // Ouverture au lancement sur le premier écran seulement.
            let geometry = NotchGeometry(screen: ScreenDescriptor(screen), forcePill: forcePill)
            windowControllers.append(NotchWindowController(
                screen: screen,
                geometry: geometry,
                openAfterCreate: shouldOpen && index == 0
            ))
        }
        Log.app.info("rebuilt \(self.windowControllers.count) notch window(s)")
    }

    /// Triggered when a second DynamicNotch launch posts a wake-up notification.
    /// Distributed notifications can be delivered on any thread — bounce to main.
    /// Installe un menu bar minimal avec un menu "Édition" exposant les
    /// shortcuts standard. Le menu n'est pas visible (app `.accessory`
    /// = pas de menubar dans la barre système), mais sa présence
    /// suffit à dire à macOS de router Cmd+V/C/X/A vers le first
    /// responder, ce qui permet le copier-coller dans le widget Note.
    private func installEditMenu() {
        let mainMenu = NSMenu()

        // App menu (placeholder requis pour que macOS prenne en compte
        // le mainMenu — même si invisible).
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        mainMenu.addItem(appItem)

        // Menu Édition avec les key equivalents standard.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Édition")
        editMenu.addItem(NSMenuItem(title: "Annuler",            action: Selector(("undo:")),                    keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Rétablir",           action: Selector(("redo:")),                    keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Couper",             action: #selector(NSText.cut(_:)),              keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copier",             action: #selector(NSText.copy(_:)),             keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Coller",             action: #selector(NSText.paste(_:)),            keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Tout sélectionner",  action: #selector(NSResponder.selectAll(_:)),   keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func handleWakeUpFromOtherInstance() {
        DispatchQueue.main.async { [weak self] in
            guard let vm = self?.mainWindowController?.vm else { return }
            Log.app.info("wake-up received from another launch attempt")
            vm.notchOpen(.click)
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard let controller = mainWindowController,
              let vm = controller.vm
        else { return true }
        vm.notchOpen(.click)
        return true
    }
}
