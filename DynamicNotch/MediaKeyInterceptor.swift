//
//  MediaKeyInterceptor.swift
//  DynamicNotch
//
//  Intercepte les touches média (volume up/down/mute, brightness up/down)
//  via deux mécanismes :
//   - **NSEvent global monitor** (mode lecture seule, par défaut) — observe
//     sans consommer ; le HUD natif macOS coexiste.
//   - **CGEvent.tapCreate** (.cghidEventTap, options .defaultTap) — capture
//     ET consomme (return nil dans le callback) → le HUD natif n'apparaît
//     plus, seul le nôtre est visible. Requiert la permission Accessibility.
//
//  ⚠️ La classe N'EST PAS `@MainActor` : le callback CGEvent est invoqué
//  par le système sur un thread du run loop arbitraire — appeler une
//  méthode `@MainActor` depuis ce contexte plante l'app. Tout accès à
//  l'état UI / aux singletons `@MainActor` est explicitement dispatché
//  via `DispatchQueue.main.async`.
//

import AppKit
import ApplicationServices
import Cocoa
import Combine
import CoreGraphics
import Foundation

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    /// Émis quand le volume vient d'être ajusté.
    let volumeChanged = PassthroughSubject<Float, Never>()
    let volumeMuted   = PassthroughSubject<Bool, Never>()
    /// Émis quand la luminosité vient d'être ajustée.
    let brightnessChanged = PassthroughSubject<Float, Never>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private(set) var isActive: Bool = false
    private(set) var isConsuming: Bool = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Le bootstrap (lecture des settings, abonnement Combine, install
        // initiale du monitor) doit se faire sur main — `DispatchQueue.main.async`
        // assure qu'on n'appelle pas de code MainActor depuis un thread
        // arbitraire si init est invoqué hors main.
        DispatchQueue.main.async { [weak self] in
            self?.subscribeSettings()
            self?.refreshFromSettings()
        }
    }

    // MARK: lifecycle

    /// Appel public depuis AppDelegate. Idempotent — si déjà démarré,
    /// re-évalue le mode (lecture seule vs consume) selon les settings.
    func start() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshFromSettings()
        }
    }

    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
        isConsuming = false
    }

    // MARK: settings binding

    private func subscribeSettings() {
        AppSettings.shared.$suppressNativeHUD
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshFromSettings() }
            .store(in: &cancellables)
    }

    /// Doit être appelé sur main. Bascule entre les deux modes selon le
    /// setting + la permission Accessibility.
    private func refreshFromSettings() {
        stop()
        if AppSettings.shared.suppressNativeHUD, AccessibilityHelper.isTrusted {
            installCGEventTap()
        } else {
            installNSEventMonitor()
        }
    }

    // MARK: NSEvent monitor (lecture seule)

    private func installNSEventMonitor() {
        let mask = NSEvent.EventTypeMask.systemDefined
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event)
            return event
        }
        isActive = true
        isConsuming = false
        Log.app.info("MediaKeyInterceptor : mode lecture seule")
    }

    // MARK: CGEvent tap (consume → HUD natif supprimé)

    private func installCGEventTap() {
        // CGEventType.systemDefined n'est pas exposé dans l'enum public ;
        // on utilise sa raw value (14, = NSSystemDefined).
        let systemDefinedRaw: UInt32 = 14
        let mask = CGEventMask(1) << systemDefinedRaw

        // Le callback C ne peut PAS être @MainActor — il est appelé sur
        // le thread du runloop. On utilise `passUnretained` parce que
        // self est singleton (vit toute la durée de l'app).
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return me.tapCallback(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            Log.app.error("CGEvent.tapCreate a échoué — retour au monitor NSEvent")
            installNSEventMonitor()
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        isConsuming = true
        Log.app.info("MediaKeyInterceptor : mode consommation (HUD natif supprimé)")
    }

    /// Callback du tap CGEvent. **NON-MainActor** — appelé sur un thread
    /// runloop arbitraire. Toute mutation d'état UI ou appel de singleton
    /// MainActor doit être dispatchée explicitement.
    private func tapCallback(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable si le tap a été désactivé par le système (timeout user).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                if let tap = self?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }

        // Pure parsing CGEvent — thread-safe.
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8
        else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000_FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        guard keyDown else {
            return [0, 1, 4, 5, 7].contains(keyCode) ? nil : Unmanaged.passUnretained(event)
        }

        if [0, 1, 4, 5, 7].contains(keyCode) {
            // Dispatch la logique vers main pour toucher VolumeManager (@MainActor)
            // et publier sur les Subject (thread-safe mais consommateurs sur main).
            DispatchQueue.main.async { [weak self] in
                self?.handleVolumeKey(keyCode: keyCode)
            }
            return nil // consume → pas de HUD natif
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: NSEvent handler (mode lecture seule, déjà sur main)

    private func handle(event: NSEvent) {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return }
        let keyCode = Int((event.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = event.data1 & 0x0000_FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        guard keyDown else { return }
        // NSEvent monitor delivers on main, mais Swift exige le hop explicite
        // pour appeler une méthode @MainActor depuis un contexte non-isolé.
        DispatchQueue.main.async { [weak self] in
            self?.handleVolumeKey(keyCode: keyCode)
        }
    }

    /// Marqué `@MainActor` parce que `VolumeManager` l'est. Les appelants
    /// (NSEvent monitor + dispatch depuis tapCallback) garantissent qu'on
    /// arrive ici sur main.
    @MainActor
    private func handleVolumeKey(keyCode: Int) {
        VolumeManager.shared.refresh()
        switch keyCode {
        case 7, 1:                  // mute
            volumeMuted.send(VolumeManager.shared.isMuted)
        case 0, 4, 5:               // play, vol up, vol down
            volumeChanged.send(VolumeManager.shared.level)
        default:
            break
        }
    }
}
