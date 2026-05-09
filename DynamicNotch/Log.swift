//
//  Log.swift
//  DynamicNotch
//
//  Central logger. Use these instead of `print(...)`.
//
//  Why: `os.Logger` integrates with Console.app, supports privacy redaction,
//  is included in sysdiagnose bundles, and is removed at compile time when
//  log level is below the active threshold (zero overhead).
//
//  Usage:
//      Log.app.info("notch opened with reason: \(reason.rawValue, privacy: .public)")
//      Log.drop.error("failed to copy file: \(error.localizedDescription, privacy: .public)")
//

import Foundation
import os

enum Log {
    /// Subsystem identifier — appears as the source in Console.app.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.notchdrop"

    /// Lifecycle, window/view-controller events, settings changes.
    static let app = Logger(subsystem: subsystem, category: "app")

    /// File drops, persistence, thumbnail generation, share/AirDrop.
    static let drop = Logger(subsystem: subsystem, category: "drop")

    /// Single-instance handshake, lock acquisition, distributed notifications.
    static let lock = Logger(subsystem: subsystem, category: "lock")

    /// Event monitors (mouse/keyboard).
    static let event = Logger(subsystem: subsystem, category: "event")

    /// Localization / language switching.
    static let i18n = Logger(subsystem: subsystem, category: "i18n")
}
