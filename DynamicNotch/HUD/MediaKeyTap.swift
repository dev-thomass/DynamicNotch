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

import AppKit
import ApplicationServices
import Combine

/// Données partagées avec le rappel C (thread quelconque).
final class MediaKeyTapContext: @unchecked Sendable {
    let policy: MediaKeyPolicy
    let deliver: @Sendable (MediaKeyEvent) -> Void
    var port: CFMachPort?

    init(policy: MediaKeyPolicy, deliver: @escaping @Sendable (MediaKeyEvent) -> Void) {
        self.policy = policy
        self.deliver = deliver
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
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Installé une seule fois, au lancement.
    func install(router: MediaKeyRouter) {
        guard self.router == nil else { return }
        self.router = router
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

    private func createTap() {
        guard let context else { return }
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
        context.port = port
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        source = runLoopSource
    }

    private func removeTap() {
        if let port = context?.port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        context?.port = nil
        source = nil
    }
}
