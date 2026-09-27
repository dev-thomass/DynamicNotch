//
//  MediaKeyTap.swift
//  DynamicNotch
//
//  Event tap de session sur les événements système (NX_SYSDEFINED). Le
//  rappel C décide immédiatement (MediaKeyPolicy, sans MainActor) de
//  consommer ou relâcher, puis confie l'application de la touche au fil
//  principal. Créé seulement quand le remplacement est actif et
//  l'autorisation Accessibilité accordée ; réactivé si macOS le coupe.
//
//  Le tap tourne sur un fil dédié (sa propre boucle d'exécution) : un fil
//  principal occupé (rendu SwiftUI, menu modal) ne retarde plus les touches
//  de tout le système et ne fait plus couper le tap par macOS.
//

import AppKit
import ApplicationServices
import Combine

/// Données partagées avec le rappel C (fil du tap). `port` est écrit depuis
/// le fil principal et lu depuis le fil du tap : accès sous verrou.
final class MediaKeyTapContext: @unchecked Sendable {
    let policy: MediaKeyPolicy
    let deliver: @Sendable (MediaKeyEvent) -> Void

    private let lock = NSLock()
    private var storedPort: CFMachPort?

    var port: CFMachPort? {
        get { lock.withLock { storedPort } }
        set { lock.withLock { storedPort = newValue } }
    }

    init(policy: MediaKeyPolicy, deliver: @escaping @Sendable (MediaKeyEvent) -> Void) {
        self.policy = policy
        self.deliver = deliver
    }
}

/// Fil dédié au tap. Sa boucle d'exécution est gardée en vie par un port
/// factice et tourne jusqu'à la fin de l'app.
private enum MediaKeyTapThread {
    /// Transmet la boucle du fil au fil principal ; écrite avant `signal()`,
    /// lue après `wait()` : le sémaphore ordonne les deux accès.
    private final class Handoff: @unchecked Sendable {
        var runLoop: CFRunLoop?
    }

    /// Démarre le fil et attend qu'il ait publié sa boucle (quelques µs).
    static func start() -> CFRunLoop {
        let handoff = Handoff()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            handoff.runLoop = CFRunLoopGetCurrent()
            // Sans source, `CFRunLoopRun()` rendrait la main aussitôt. Le tap
            // est ajouté au même mode par défaut, celui où tourne `CFRunLoopRun()`.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "DynamicNotch.MediaKeyTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        guard let runLoop = handoff.runLoop else {
            preconditionFailure("boucle du fil du tap non publiée")
        }
        return runLoop
    }
}

private func mediaKeyTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<MediaKeyTapContext>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = context.port { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, // NX_SYSDEFINED
          let nsEvent = NSEvent(cgEvent: event),
          let keyEvent = MediaKeyEvent.decode(
              subtype: Int(nsEvent.subtype.rawValue),
              data1: nsEvent.data1,
              modifiers: nsEvent.modifierFlags
          ),
          context.policy.shouldConsume(keyEvent.key)
    else { return Unmanaged.passUnretained(event) }

    context.deliver(keyEvent)
    return nil
}

@MainActor
final class MediaKeyTap {
    static let shared = MediaKeyTap()

    private var router: MediaKeyRouter?
    private var context: MediaKeyTapContext?
    private var source: CFRunLoopSource?
    /// Boucle du fil dédié, créée une fois dans `install`.
    private var tapRunLoop: CFRunLoop?
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Installé une seule fois, au lancement.
    func install(router: MediaKeyRouter) {
        guard self.router == nil else { return }
        self.router = router
        // Le puits Combine plus bas livre la valeur de façon asynchrone : sans
        // ceci, le premier `refresh()` utiliserait la valeur par défaut du routeur.
        router.replaceEnabled = AppSettings.shared.replaceSystemHUD
        tapRunLoop = MediaKeyTapThread.start()
        context = MediaKeyTapContext(policy: router.policy) { event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { MediaKeyTap.shared.router?.apply(event) }
            }
        }

        AppSettings.shared.$replaceSystemHUD
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.router?.replaceEnabled = enabled
                self?.refresh()
            }
            .store(in: &cancellables)

        // L'autorisation peut arriver pendant que l'app tourne : relecture toutes les 2 s.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
        refresh()
    }

    /// Ouvre l'invite système d'autorisation Accessibilité.
    func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func refresh() {
        guard let router else { return }
        router.trusted = isTrusted
        router.refreshPolicy()
        let wanted = router.replaceEnabled && router.trusted
        if wanted, source == nil {
            createTap()
        } else if !wanted, source != nil {
            removeTap()
        }
    }

    /// Fil principal. `CFRunLoopAddSource` et `CFRunLoopWakeUp` sont sûrs
    /// depuis un autre fil que celui de la boucle.
    private func createTap() {
        guard let context, let tapRunLoop else { return }
        let refcon = Unmanaged.passUnretained(context).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << 14),
            callback: mediaKeyTapCallback,
            userInfo: refcon
        ) else {
            Log.app.error("création du tap des touches système impossible")
            return
        }
        // Avant l'ajout de la source : le rappel peut lire `port` dès qu'elle tourne.
        context.port = port
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(tapRunLoop, runLoopSource, .defaultMode)
        CGEvent.tapEnable(tap: port, enable: true)
        CFRunLoopWakeUp(tapRunLoop)
        source = runLoopSource
    }

    /// Fil principal. `port` est d'abord retiré du contexte : un rappel en
    /// cours sur le fil du tap ne peut plus réactiver le tap qu'on coupe.
    private func removeTap() {
        let port = context?.port
        context?.port = nil
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source, let tapRunLoop {
            CFRunLoopRemoveSource(tapRunLoop, source, .defaultMode)
            CFRunLoopWakeUp(tapRunLoop)
        }
        if let port {
            CFMachPortInvalidate(port)
        }
        source = nil
    }
}
