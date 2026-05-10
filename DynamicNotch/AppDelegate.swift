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

    /// Re-read each time we need it (was cached at launch and never refreshed).
    /// Cheap call, no need to memoize.
    var isLaunchedAtLogin: Bool { LaunchAtLogin.wasLaunchedAtLogin }

    func applicationDidFinishLaunching(_: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildApplicationWindows),
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
        // Singletons des managers utilisés par les wings.
        _ = BatteryMonitor.shared

        // Rebuild the windows when the user picks a different display
        // OU bascule "afficher sur tous les écrans".
        Publishers.CombineLatest(
            AppSettings.shared.$displayPreference.removeDuplicates(),
            AppSettings.shared.$showOnAllScreens.removeDuplicates()
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            Log.app.info("display setting changed, rebuilding windows")
            self?.rebuildApplicationWindows()
        }
        .store(in: &settingsObservers)

        rebuildApplicationWindows()
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

    @objc func rebuildApplicationWindows() {
        defer { isFirstOpen = false }
        // Détruit toutes les windows existantes proprement.
        windowControllers.forEach { $0.destroy() }
        windowControllers.removeAll()

        // Liste des écrans à équiper :
        //  - si `showOnAllScreens` : tous les NSScreen connectés
        //  - sinon : juste celui désigné par `displayPreference`
        let screens: [NSScreen]
        if AppSettings.shared.showOnAllScreens {
            screens = NSScreen.screens
        } else if let one = findScreenFitsOurNeeds() {
            screens = [one]
        } else {
            screens = []
        }

        let shouldOpen = isFirstOpen && !isLaunchedAtLogin
        for (index, screen) in screens.enumerated() {
            // openAfterCreate uniquement sur le 1er écran (pour ne pas
            // ouvrir l'encoche partout au boot).
            let controller = NotchWindowController(
                screen: screen,
                openAfterCreate: shouldOpen && index == 0
            )
            windowControllers.append(controller)
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

import Combine
