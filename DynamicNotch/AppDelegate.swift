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

        _ = EventMonitors.shared
        // Démarre les managers + tap des touches média pour afficher le HUD
        // sous l'encoche dès le premier appui sur volume / luminosité.
        _ = BatteryMonitor.shared
        _ = VolumeManager.shared
        _ = BrightnessManager.shared
        MediaKeyInterceptor.shared.start()
        _ = HUDController.shared

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
