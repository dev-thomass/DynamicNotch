//
//  VolumeFeedback.swift
//  DynamicNotch
//
//  Petit son joué après un changement de volume, comme macOS quand
//  « Émettre un son lors du changement de volume » est coché.
//

import AppKit

@MainActor
enum VolumeFeedback {
    /// Préférence macOS (domaine global) « com.apple.sound.beep.feedback ».
    static var systemPreference: Bool {
        (UserDefaults.standard.object(forKey: "com.apple.sound.beep.feedback") as? Int) == 1
    }

    static var isEnabled: Bool {
        AppSettings.shared.volumeFeedback ?? systemPreference
    }

    private static let sound: NSSound? =
        NSSound(contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff", byReference: true)
        ?? NSSound(named: "Pop")

    static func play() {
        guard isEnabled, let sound else { return }
        sound.stop()
        sound.play()
    }
}
