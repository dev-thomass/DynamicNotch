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

    /// Notification publiée quand le mode change (lecture seule / consume /
    /// failed). Le Settings UI s'abonne pour afficher un statut live.
    static let statusChangedNotification = Notification.Name("MediaKeyInterceptorStatusChanged")

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
        NotificationCenter.default.post(name: Self.statusChangedNotification, object: nil)
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
            // Cause la plus fréquente : la permission Accessibility a été
            // accordée à un binaire signé différemment (rebuild ad-hoc =
            // nouveau hash → permission révoquée silencieusement). L'utilisateur
            // doit retirer l'app de la liste Accessibilité puis la rajouter.
            Log.app.error("""
                CGEvent.tapCreate a échoué malgré AXIsProcessTrusted=true.
                Cause probable : permission Accessibility révoquée par un
                rebuild ad-hoc. Retirer DynamicNotch de Réglages → Confidentialité
                → Accessibilité, puis rajouter le binaire actuel.
                Fallback NSEvent activé.
                """)
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
        Log.app.info("MediaKeyInterceptor : mode consommation actif (HUD natif supprimé)")
        NotificationCenter.default.post(name: Self.statusChangedNotification, object: nil)
    }

    /// Callback du tap CGEvent. **NON-MainActor** — appelé sur un thread
    /// runloop arbitraire. Toute mutation d'état UI ou appel de singleton
    /// MainActor doit être dispatchée explicitement.
    ///
    /// **Important** : quand on retourne `nil` (consume), le système ne
    /// traite plus l'event → le volume / la luminosité ne change pas
    /// tout seul. On doit nous-mêmes appeler `setVolume` / `setBrightness`
    /// pour appliquer le changement.
    private func tapCallback(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                if let tap = self?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8
        else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000_FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0xA

        // Codes officiels (NX_KEYTYPE_*):
        //  2 = brightness up, 3 = brightness down
        //  4 = volume up, 5 = volume down, 7 = mute
        let mediaKeys: Set<Int> = [2, 3, 4, 5, 7]
        guard mediaKeys.contains(keyCode) else {
            return Unmanaged.passUnretained(event)
        }
        // Consomme aussi le keyUp pour que le HUD natif ne réapparaisse pas.
        guard keyDown else { return nil }

        DispatchQueue.main.async { [weak self] in
            self?.applyMediaAction(keyCode: keyCode)
        }
        return nil // consume → pas de HUD natif
    }

    // MARK: NSEvent handler (mode lecture seule, déjà sur main)

    private func handle(event: NSEvent) {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return }
        let keyCode = Int((event.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = event.data1 & 0x0000_FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        guard keyDown else { return }
        // Mode lecture seule : on observe uniquement, le système gère
        // toujours le changement de volume / luminosité. On notifie juste
        // le HUD pour qu'il s'affiche.
        DispatchQueue.main.async { [weak self] in
            self?.notifyObservers(keyCode: keyCode)
        }
    }

    /// Mode CONSUME : on a empêché le système de traiter l'event, donc on
    /// applique le changement nous-mêmes (incrément volume, set brightness)
    /// puis on notifie le HUD.
    /// Pas de step trop fin sinon les keyDown répétés (auto-repeat) sautent.
    @MainActor
    private func applyMediaAction(keyCode: Int) {
        let step: Float = 1.0 / 16.0  // = 6.25 % par appui (16 paliers)
        switch keyCode {
        case 4: // volume up
            let new: Float = min(Float(1), VolumeManager.shared.level + step)
            VolumeManager.shared.setVolume(new)
        case 5: // volume down
            let new: Float = max(Float(0), VolumeManager.shared.level - step)
            VolumeManager.shared.setVolume(new)
        case 7: // mute toggle
            VolumeManager.shared.setMuted(!VolumeManager.shared.isMuted)
        case 2: // brightness up
            let new: Float = min(Float(1), BrightnessManager.shared.level + step)
            BrightnessManager.shared.setBrightness(new)
        case 3: // brightness down
            let new: Float = max(Float(0), BrightnessManager.shared.level - step)
            BrightnessManager.shared.setBrightness(new)
        default:
            break
        }
        notifyObservers(keyCode: keyCode)
    }

    /// Notifie les observateurs (HUD) du changement. Lit la valeur ACTUELLE
    /// post-changement et l'envoie via les Subject.
    @MainActor
    private func notifyObservers(keyCode: Int) {
        switch keyCode {
        case 7, 1:               // mute
            volumeMuted.send(VolumeManager.shared.isMuted)
        case 4, 5, 0:            // volume up/down/play
            volumeChanged.send(VolumeManager.shared.level)
        case 2, 3:               // brightness up/down
            brightnessChanged.send(BrightnessManager.shared.level)
        default:
            break
        }
    }
}
