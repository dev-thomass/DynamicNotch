//
//  ActivityScheduler.swift
//  DynamicNotch
//
//  Minuterie injectable d'ActivityCenter. En production, la file principale ;
//  en test, une minuterie manuelle qui avance le temps de façon synchrone.
//

import Foundation

@MainActor
protocol ActivityScheduler: AnyObject {
    var now: Date { get }
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork
}

/// Travail planifié, annulable une seule fois.
@MainActor
final class ScheduledWork {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}

@MainActor
final class MainQueueScheduler: ActivityScheduler {
    var now: Date {
        Date()
    }

    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork {
        let item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return ScheduledWork { item.cancel() }
    }
}
