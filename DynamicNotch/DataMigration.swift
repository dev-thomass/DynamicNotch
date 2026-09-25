//
//  DataMigration.swift
//  DynamicNotch
//
//  Migration unique des données de ~/Documents/DynamicNotch vers
//  ~/Library/Application Support/DynamicNotch (ou leur équivalent dans le
//  conteneur quand l'app est sandboxée : on passe toujours par FileManager).
//  Seules les clés encore lues par l'app sont reprises ; l'ancien dossier
//  reste en place.
//

import Foundation

enum DataMigration {
    static let markerName = ".migrated-v1"

    /// Fichiers de `Config/` encore utilisés. Les clés périmées d'anciennes
    /// versions (notchOpacity, prompterText, isProUnlocked, …) sont ignorées.
    static let configFiles: Set<String> = [
        "TrayDropItems", "alwaysVisibleWhenClosed", "customStorageTime",
        "customStorageTimeUnit", "displayPreference", "escClosesNotch",
        "forcePillMode", "hapticFeedback", "keepInterval",
        "pomodoroCyclesBeforeLongBreak", "pomodoroFocusMinutes",
        "pomodoroLongBreakMinutes", "pomodoroShortBreakMinutes",
        "popOnHoverEnabled", "quickNote.txt", "selectedFileStorageTime",
        "selectedLanguage", "showOnAllScreens", "widgetPages", "wingBattery",
        "wingCalendar", "wingPomodoro", "wingStopwatch", "wingsEnabled",
    ]

    static func run(from legacy: URL, to destination: URL, fileManager: FileManager = .default) {
        let marker = destination.appendingPathComponent(markerName)
        guard !fileManager.fileExists(atPath: marker.path) else { return }

        let legacyConfig = legacy.appendingPathComponent("Config")
        let config = destination.appendingPathComponent("Config")
        try? fileManager.createDirectory(at: config, withIntermediateDirectories: true)
        for name in configFiles {
            copyIfAbsent(legacyConfig.appendingPathComponent(name), to: config.appendingPathComponent(name), fileManager)
        }
        copyIfAbsent(
            legacy.appendingPathComponent("CopiedItems"),
            to: destination.appendingPathComponent("CopiedItems"),
            fileManager
        )
        fileManager.createFile(atPath: marker.path, contents: Data())
    }

    private static func copyIfAbsent(_ source: URL, to target: URL, _ fileManager: FileManager) {
        guard fileManager.fileExists(atPath: source.path),
              !fileManager.fileExists(atPath: target.path)
        else { return }
        try? fileManager.copyItem(at: source, to: target)
    }
}
