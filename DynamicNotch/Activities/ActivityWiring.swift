//
//  ActivityWiring.swift
//  DynamicNotch
//
//  Branche les sources (batterie, Pomodoro, chrono, plateau, AirDrop,
//  calendrier) sur ActivityCenter. Les événements ponctuels sont postés tels
//  quels ; l'état persistant est recalculé à chaque changement d'une source
//  ou d'un réglage, et toutes les 30 s (décompte du calendrier).
//

import AppKit
import Combine

@MainActor
final class ActivityWiring {
    static let shared = ActivityWiring()

    /// Tout ce dont dépend l'état persistant, à un instant donné.
    struct Inputs {
        var wingsEnabled: Bool
        var wingBattery: Bool
        var wingStopwatch: Bool
        var wingPomodoro: Bool
        var wingCalendar: Bool
        var battery: PowerSnapshot
        var stopwatchHasTime: Bool
        var pomodoroActive: Bool
        var musicPlaying: Bool
        var nextEventStart: Date?
        var now: Date
    }

    static let persistentIDs: [ActivityID] = [.charging, .stopwatch, .pomodoroPhase, .nowPlaying, .calendarSoon]

    static func activePersistent(_ inputs: Inputs) -> Set<ActivityID> {
        guard inputs.wingsEnabled else { return [] }
        var active: Set<ActivityID> = []
        if inputs.wingBattery, inputs.battery.hasBattery, inputs.battery.isPluggedIn { active.insert(.charging) }
        if inputs.wingStopwatch, inputs.stopwatchHasTime { active.insert(.stopwatch) }
        if inputs.wingPomodoro, inputs.pomodoroActive { active.insert(.pomodoroPhase) }
        if inputs.musicPlaying { active.insert(.nowPlaying) }
        if inputs.wingCalendar, let start = inputs.nextEventStart {
            let delay = start.timeIntervalSince(inputs.now)
            if delay > 0, delay < 60 * 60 { active.insert(.calendarSoon) }
        }
        return active
    }

    static func activity(for event: PowerEvent) -> ActivityID {
        switch event {
        case .pluggedIn: .charging
        case .unplugged: .unplugged
        case let .lowBattery(percent): .lowBattery(percent: percent)
        }
    }

    private let center: ActivityCenter
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    // Le défaut `.shared` est résolu dans le corps plutôt qu'en valeur par
    // défaut de paramètre : une valeur par défaut n'hérite pas de
    // l'isolation MainActor de l'initialiseur, ce qui déclenche un
    // avertissement (erreur en Swift 6) sur l'accès à `ActivityCenter.shared`.
    init(center: ActivityCenter? = nil) {
        self.center = center ?? .shared
    }

    func install() {
        guard timer == nil else { return } // installé une seule fois
        BatteryMonitor.shared.onChange = { [weak self] _, events in
            guard let self else { return }
            for event in events {
                center.post(Self.activity(for: event))
            }
            reevaluate()
        }
        PomodoroModel.shared.onPhaseChange = { [weak self] _, naturalEnd in
            if naturalEnd { NSSound(named: "Glass")?.play() }
            self?.center.post(.pomodoroPhase)
        }
        // Ces deux rappels sont documentés « sur la file principale », mais un
        // délégué système pourrait les appeler ailleurs : on repasse toujours
        // par la file principale plutôt que de l'affirmer (plantage sinon).
        TrayDrop.shared.onItemsAdded = { [weak self] count in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.center.post(.filesAdded(count: count)) }
            }
        }
        Share.onAirDropSent = { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.center.post(.airDropSent) }
            }
        }

        let settings = AppSettings.shared
        let triggers: [AnyPublisher<Void, Never>] = [
            settings.$wingsEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$wingBattery.map { _ in () }.eraseToAnyPublisher(),
            settings.$wingStopwatch.map { _ in () }.eraseToAnyPublisher(),
            settings.$wingPomodoro.map { _ in () }.eraseToAnyPublisher(),
            settings.$wingCalendar.map { _ in () }.eraseToAnyPublisher(),
            PomodoroModel.shared.$phase.map { _ in () }.eraseToAnyPublisher(),
            StopwatchModel.shared.$running.map { _ in () }.eraseToAnyPublisher(),
            StopwatchModel.shared.$accumulated.map { _ in () }.eraseToAnyPublisher(),
            CalendarStore.shared.$nextEvent.map { _ in () }.eraseToAnyPublisher(),
        ]
        // receive(on:) : @Published émet avant l'écriture, on relit après.
        Publishers.MergeMany(triggers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reevaluate() }
            .store(in: &cancellables)

        let newTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluate() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        reevaluate()
    }

    func reevaluate() {
        let settings = AppSettings.shared
        let inputs = Inputs(
            wingsEnabled: settings.wingsEnabled,
            wingBattery: settings.wingBattery,
            wingStopwatch: settings.wingStopwatch,
            wingPomodoro: settings.wingPomodoro,
            wingCalendar: settings.wingCalendar,
            battery: BatteryMonitor.shared.snapshot,
            stopwatchHasTime: StopwatchModel.shared.hasTime,
            pomodoroActive: PomodoroModel.shared.phase != .idle,
            musicPlaying: false, // activé par la tâche 12 (MediaRemote)
            nextEventStart: CalendarStore.shared.nextEvent?.startDate,
            now: Date()
        )
        let active = Self.activePersistent(inputs)
        for id in Self.persistentIDs {
            center.setPersistent(id, active: active.contains(id))
        }
    }
}
