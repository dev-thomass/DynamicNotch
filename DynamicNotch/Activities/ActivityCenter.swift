//
//  ActivityCenter.swift
//  DynamicNotch
//
//  Arbitre unique des activités, partagé par tous les écrans.
//   - Une ponctuelle en cours → mode étendu pendant sa durée.
//   - Sinon la persistante de plus haute priorité → mode compact.
//   - Ponctuelles suivantes : en file, dans l'ordre d'arrivée ; abandonnées
//     après `staleAfter` secondes d'attente ; la même que celle en cours la
//     prolonge.
//   - Suspendu (panneau ouvert par l'utilisateur) : les ponctuelles sont
//     ignorées, les persistantes continuent d'être suivies.
//

import Foundation

@MainActor
final class ActivityCenter {
    static let shared = ActivityCenter(scheduler: MainQueueScheduler())
    static let staleAfter: TimeInterval = 5

    private struct Pending {
        let id: ActivityID
        let postedAt: Date
    }

    private(set) var current: ActivityDisplay?

    private let scheduler: ActivityScheduler
    private var transient: Pending?
    private var queue: [Pending] = []
    private var persistent: Set<ActivityID> = []
    private var endWork: ScheduledWork?
    private var suspensionCount = 0
    private var observers: [UUID: (ActivityDisplay?) -> Void] = [:]

    init(scheduler: ActivityScheduler) {
        self.scheduler = scheduler
    }

    var isSuspended: Bool { suspensionCount > 0 }

    func post(_ id: ActivityID) {
        guard !isSuspended else { return }
        let pending = Pending(id: id, postedAt: scheduler.now)
        if transient == nil || transient?.id == id {
            start(pending)
        } else {
            queue.removeAll { $0.id == id }
            queue.append(pending)
        }
    }

    func setPersistent(_ id: ActivityID, active: Bool) {
        let changed = active ? persistent.insert(id).inserted : persistent.remove(id) != nil
        if changed { recompute() }
    }

    func beginSuspension() {
        suspensionCount += 1
        endWork?.cancel()
        endWork = nil
        transient = nil
        queue.removeAll()
        recompute()
    }

    func endSuspension() {
        suspensionCount = max(0, suspensionCount - 1)
        recompute()
    }

    @discardableResult
    func observe(_ handler: @escaping (ActivityDisplay?) -> Void) -> ActivityObservation {
        let key = UUID()
        observers[key] = handler
        return ActivityObservation { [weak self] in
            self?.observers[key] = nil
        }
    }

    // MARK: interne

    private func start(_ pending: Pending) {
        endWork?.cancel()
        transient = pending
        endWork = scheduler.schedule(after: pending.id.transientDuration) { [weak self] in
            self?.finishTransient()
        }
        recompute()
    }

    private func finishTransient() {
        endWork = nil
        transient = nil
        let now = scheduler.now
        queue.removeAll { now.timeIntervalSince($0.postedAt) > Self.staleAfter }
        if queue.isEmpty {
            recompute()
        } else {
            start(queue.removeFirst())
        }
    }

    private func recompute() {
        let next: ActivityDisplay?
        if let transient {
            next = ActivityDisplay(id: transient.id, mode: .expanded)
        } else if let top = persistent.max(by: { $0.persistentPriority < $1.persistentPriority }) {
            next = ActivityDisplay(id: top, mode: .compact)
        } else {
            next = nil
        }
        guard next != current else { return }
        current = next
        for handler in observers.values {
            handler(next)
        }
    }
}

/// Jeton d'abonnement à `ActivityCenter`. `cancel()` désabonne.
@MainActor
final class ActivityObservation {
    private var onCancel: (() -> Void)?

    init(_ onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}
