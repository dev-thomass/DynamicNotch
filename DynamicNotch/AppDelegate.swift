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
    var mainWindowController: NotchWindowController?
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

        // Rebuild the windows when the user picks a different display.
        AppSettings.shared.$displayPreference
            .removeDuplicates()
            .dropFirst() // skip the initial value, we rebuild explicitly below
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Log.app.info("display preference changed, rebuilding windows")
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
        if let mainWindowController {
            mainWindowController.destroy()
        }
        mainWindowController = nil
        guard let mainScreen = findScreenFitsOurNeeds() else { return }

        // Decide *before* constructing the controller — its initializer reads
        // `openAfterCreate` synchronously now (T-22 init refactor), so a
        // post-init assignment would arrive too late. The pre-T-22 code relied
        // on a 100 ms asyncAfter to mask this race.
        let shouldOpen = isFirstOpen && !isLaunchedAtLogin
        mainWindowController = .init(screen: mainScreen, openAfterCreate: shouldOpen)
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
