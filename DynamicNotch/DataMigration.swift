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
        "wingCalendar", "wingPomodoro", "wingStopwatch", "wingsEnabled"
    ]

    static func run(from legacy: URL, to destination: URL, fileManager: FileManager = .default) {
        let marker = destination.appendingPathComponent(markerName)
        guard !fileManager.fileExists(atPath: marker.path) else { return }

        // Ancien dossier présent mais illisible (permissions…) : on ne pose
        // pas le marqueur, la migration sera retentée au prochain lancement.
        if fileManager.fileExists(atPath: legacy.path) {
            do {
                _ = try fileManager.contentsOfDirectory(atPath: legacy.path)
            } catch {
                Log.app.error("migration: ancien dossier illisible: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        let legacyConfig = legacy.appendingPathComponent("Config")
        let config = destination.appendingPathComponent("Config")
        try? fileManager.createDirectory(at: config, withIntermediateDirectories: true)
        var succeeded = true
        for name in configFiles {
            succeeded = copyIfAbsent(
                legacyConfig.appendingPathComponent(name),
                to: config.appendingPathComponent(name),
                fileManager
            ) && succeeded
        }
        succeeded = copyIfAbsent(
            legacy.appendingPathComponent("CopiedItems"),
            to: destination.appendingPathComponent("CopiedItems"),
            fileManager
        ) && succeeded
        // Marqueur seulement si toutes les copies tentées ont réussi.
        guard succeeded else { return }
        fileManager.createFile(atPath: marker.path, contents: Data())
    }

    /// Copie `source` vers `target` s'il existe et que `target` est absent.
    /// Renvoie `false` seulement si une copie tentée a échoué.
    private static func copyIfAbsent(_ source: URL, to target: URL, _ fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: source.path),
              !fileManager.fileExists(atPath: target.path) else { return true }
        do {
            try fileManager.copyItem(at: source, to: target)
            return true
        } catch {
            Log.app
                .error(
                    "migration: copie impossible de \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            return false
        }
    }
}
