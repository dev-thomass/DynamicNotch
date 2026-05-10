//
//  MediaKeyInterceptor.swift
//  DynamicNotch
//
//  Intercepte les touches media (volume up/down/mute, brightness up/down)
//  via un CGEvent tap système. Quand activé, le HUD natif macOS ne s'affiche
//  pas — c'est notre HUD sous l'encoche qui prend le relais.
//
//  Permission requise : Accessibility (Réglages → Confidentialité → Acc.).
//  Sans cette permission, le tap échoue silencieusement — on log un avis
//  et on reste en mode "lecture seule" (le HUD apparaît quand l'utilisateur
//  utilise déjà les touches mais on ne court-circuite pas le HUD système).
//

import Cocoa
import Combine
import CoreGraphics
import Foundation
import ApplicationServices

@MainActor
final class MediaKeyInterceptor: ObservableObject {
    static let shared = MediaKeyInterceptor()

    /// Émis quand le volume vient d'être ajusté (par les touches ou par
    /// nous-mêmes via setVolume). Le HUD écoute pour s'afficher.
    let volumeChanged = PassthroughSubject<Float, Never>()
    let volumeMuted   = PassthroughSubject<Bool, Never>()

    /// Émis quand la luminosité vient d'être ajustée.
    let brightnessChanged = PassthroughSubject<Float, Never>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isActive: Bool = false
    /// `true` quand on intercepte ET consomme les events (HUD natif supprimé).
    /// `false` en mode lecture seule via NSEvent.
    private(set) var isConsuming: Bool = false

    private init() {
        // Démarrage initial selon le setting persisté.
        DispatchQueue.main.async { [weak self] in
            self?.refreshFromSettings()
        }
        // Re-évalue quand le setting change.
        AppSettings.shared.$suppressNativeHUD
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshFromSettings() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: lifecycle

    /// Démarre l'interception. Appelée une fois depuis AppDelegate.
    /// Le mode (lecture seule vs consommation) est piloté par le setting
    /// `AppSettings.suppressNativeHUD`.
    func start() {
        refreshFromSettings()
    }

    /// Re-démarre dans le bon mode selon `suppressNativeHUD` + permission
    /// Accessibility.
    private func refreshFromSettings() {
        stop()
        if AppSettings.shared.suppressNativeHUD, AccessibilityHelper.isTrusted {
            installCGEventTap()
        } else {
            installNSEventMonitor()
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

    // MARK: NSEvent global monitor (lecture seule, HUD natif coexiste)

    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Mode "lecture seule" : on observe les touches média quand elles
    /// arrivent à n'importe quelle app, mais on ne les *consomme pas*.
    /// Le HUD natif macOS s'affiche en plus du nôtre — utilisé en
    /// fallback quand la permission Accessibility n'est pas accordée.
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
        Log.app.info("MediaKeyInterceptor : mode lecture seule (HUD natif coexistant)")
    }

    // MARK: CGEvent tap (consume → HUD natif supprimé)

    /// Mode "consommation" : on installe un tap CGEvent au niveau HID.
    /// Quand une touche média arrive, on la lit, on la traite, puis on
    /// retourne `nil` → le système ne la voit pas → pas de HUD natif.
    /// Requiert la permission Accessibility (sinon `tapCreate` retourne nil).
    private func installCGEventTap() {
        // CGEventType.systemDefined n'est pas exposé directement, on doit
        // utiliser la valeur brute (14 = NSSystemDefined). On l'inclut dans
        // le bit-mask des events à observer.
        let systemDefinedType: CGEventType = .init(rawValue: 14)!
        let mask = (1 << systemDefinedType.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.tapCallback(proxy: proxy, type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            Log.app.error("CGEvent.tapCreate a échoué — fallback NSEvent (lecture seule)")
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

    /// Callback du CGEventTap. Si l'event est une touche média, on la
    /// traite + on retourne nil pour la consommer. Sinon on la laisse
    /// passer.
    private func tapCallback(
        proxy _: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enable si le tap a été désactivé par le système (timeout, etc.)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Convertit en NSEvent pour réutiliser la logique existante.
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8
        else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = (nsEvent.data1 & 0xFFFF_0000) >> 16
        // Touches volume / mute : on consomme.
        if [0, 1, 4, 5, 7].contains(keyCode) {
            handle(event: nsEvent)
            return nil // consume → pas de HUD natif
        }
        return Unmanaged.passUnretained(event)
    }

    private func handle(event: NSEvent) {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return }

        let keyCode = (event.data1 & 0xFFFF_0000) >> 16
        let keyFlags = event.data1 & 0x0000_FFFF
        let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA  // 0xA = key down

        guard keyState else { return }

        // Codes officiels (NSEventSubtypeAuxControlButtons)
        // 0  = play/pause, 1 = next, 2 = prev, 3 = mute, 4 = vol up, 5 = vol down
        // brightness up/down ne sont PAS exposées en .systemDefined côté
        // user-space sur les Mac récents — Apple les route directement à
        // DisplayServices. On expose donc seulement le volume ici.
        switch keyCode {
        case 7, 1: // mute
            VolumeManager.shared.refresh()
            volumeMuted.send(VolumeManager.shared.isMuted)
        case 0, 4: // volume up
            VolumeManager.shared.refresh()
            volumeChanged.send(VolumeManager.shared.level)
        case 5: // volume down
            VolumeManager.shared.refresh()
            volumeChanged.send(VolumeManager.shared.level)
        default:
            break
        }
    }
}
