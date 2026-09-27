//
//  HUDController.swift
//  DynamicNotch
//
//  Canal du HUD, prioritaire sur les activités : un état affiché 1,5 s après
//  le dernier changement. Partagé par toutes les encoches.
//

import Combine
import Foundation

@MainActor
final class HUDController: ObservableObject {
    static let shared = HUDController(scheduler: MainQueueScheduler())
    static let displayDuration: TimeInterval = 1.5

    @Published private(set) var current: HUDState?
    /// Dernier état affiché, conservé pendant l'animation de sortie.
    private(set) var lastShown: HUDState?

    private let scheduler: ActivityScheduler
    private var hideWork: ScheduledWork?
    private var observers: [UUID: (HUDState?) -> Void] = [:]

    init(scheduler: ActivityScheduler) {
        self.scheduler = scheduler
    }

    /// Affiche (ou met à jour) le HUD et repousse sa disparition.
    func show(_ state: HUDState) {
        hideWork?.cancel()
        lastShown = state
        hideWork = scheduler.schedule(after: Self.displayDuration) { [weak self] in
            self?.hide()
        }
        guard state != current else { return }
        current = state
        notify()
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        guard current != nil else { return }
        current = nil
        notify()
    }

    @discardableResult
    func observe(_ handler: @escaping (HUDState?) -> Void) -> ActivityObservation {
        let key = UUID()
        observers[key] = handler
        return ActivityObservation { [weak self] in
            self?.observers[key] = nil
        }
    }

    private func notify() {
        for handler in observers.values {
            handler(current)
        }
    }
}
