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

    private init() {}

    // MARK: lifecycle

    /// Tente d'installer le tap. À appeler depuis `applicationDidFinishLaunching`
    /// si l'utilisateur a activé l'interception dans les réglages.
    func start() {
        guard eventTap == nil else { return }
        // Les touches media génèrent des events de type
        // NSEventType.systemDefined avec subtype 8 (NSEventSubtypeAuxControlButtons).
        // On capte la couche basse via CGEventType.systemDefined si dispo,
        // sinon via NSEvent.addGlobalMonitorForEvents.
        installNSEventMonitor()
    }

    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
    }

    // MARK: NSEvent global monitor (sans suppression du HUD natif)

    private var globalMonitor: Any?

    /// Mode "lecture seule" : on observe les touches media quand elles
    /// arrivent à n'importe quelle app, mais on ne les *consomme pas*. Le
    /// HUD natif macOS s'affiche en plus du nôtre — pas idéal mais ne
    /// nécessite pas la permission Accessibility.
    private func installNSEventMonitor() {
        let mask = NSEvent.EventTypeMask.systemDefined
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event)
        }
        // Local monitor pour aussi capter quand notre app est au premier plan
        NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event)
            return event
        }
        isActive = true
        Log.app.info("MediaKeyInterceptor démarré (mode lecture seule, HUD natif non supprimé)")
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
