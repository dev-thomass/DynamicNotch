//
//  Widget.swift
//  DynamicNotch
//
//  Catalog of available widgets that can populate a page in the notch panel.
//
//  Adding a widget:
//   1. Add a `case` here.
//   2. Add a SwiftUI `View` conforming to standard signature `init(vm:)`.
//   3. Wire it into the `widgetView(for:)` switch in `NotchContentView`.
//   4. (Optional) add an icon + label override below.
//

import Foundation
import SwiftUI

extension NotchViewModel {

    enum Widget: String, Codable, Hashable, CaseIterable, Identifiable {
        // ─── File / share family ─────────────────────────────────────────────
        case airdrop
        case files

        // ─── Personal / scheduling ───────────────────────────────────────────
        case calendar
        case notes

        // ─── Time-keeping ────────────────────────────────────────────────────
        case stopwatch
        case pomodoro

        // ─── Media ───────────────────────────────────────────────────────────
        case nowPlaying

        public var id: String { rawValue }

        // MARK: legacy migration

        /// Decodes legacy raw values from older builds (`"timer"` /
        /// `"countdown"` mapped to the consolidated `.stopwatch`).
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "timer", "countdown":
                self = .stopwatch
            default:
                guard let val = Widget(rawValue: raw) else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath,
                              debugDescription: "Unknown widget raw value: \(raw)")
                    )
                }
                self = val
            }
        }

        // MARK: presentation

        /// SF Symbol shown in the Settings widget picker.
        public var icon: String {
            switch self {
            case .airdrop:    "dot.radiowaves.up.forward"
            case .files:      "tray.and.arrow.down.fill"
            case .calendar:   "calendar"
            case .notes:      "note.text"
            case .stopwatch:  "stopwatch"
            case .pomodoro:   "brain.head.profile"
            case .nowPlaying: "music.note"
            }
        }

        /// User-facing label (kept short for the small panel real estate).
        public var label: LocalizedStringKey {
            switch self {
            case .airdrop:    "AirDrop"
            case .files:      "Fichiers"
            case .calendar:   "Agenda"
            case .notes:      "Notes"
            case .stopwatch:  "Chrono"
            case .pomodoro:   "Focus"
            case .nowPlaying: "Musique"
            }
        }
    }
}
