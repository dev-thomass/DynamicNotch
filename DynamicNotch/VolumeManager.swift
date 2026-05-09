//
//  VolumeManager.swift
//  DynamicNotch
//
//  Lit et écrit le volume du périphérique de sortie audio par défaut via
//  CoreAudio HAL. Publie le niveau actuel (0..1) et l'état muet pour que
//  le HUD puisse les afficher en temps réel.
//

import AudioToolbox
import Combine
import CoreAudio
import Foundation

@MainActor
final class VolumeManager: ObservableObject {
    static let shared = VolumeManager()

    @Published private(set) var level: Float = 0.5
    @Published private(set) var isMuted: Bool = false

    private var listenerSetup = false

    private init() {
        refresh()
        installListener()
    }

    // MARK: read

    func refresh() {
        guard let dev = defaultOutputDeviceID() else { return }
        if let v = volumeOf(deviceID: dev) { level = v }
        if let m = muteOf(deviceID: dev)   { isMuted = m }
    }

    // MARK: write

    /// Définit le volume sur l'output par défaut. Délégué à
    /// `MediaKeyInterceptor.adjustVolume(...)` pour les pas haut/bas.
    func setVolume(_ newValue: Float) {
        let clamped = min(1, max(0, newValue))
        guard let dev = defaultOutputDeviceID() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var v = clamped
        AudioObjectSetPropertyData(dev, &addr, 0, nil,
                                   UInt32(MemoryLayout<Float>.size), &v)
        level = clamped
    }

    func setMuted(_ value: Bool) {
        guard let dev = defaultOutputDeviceID() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var m: UInt32 = value ? 1 : 0
        AudioObjectSetPropertyData(dev, &addr, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &m)
        isMuted = value
    }

    // MARK: helpers

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dev: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &dev
        )
        return status == noErr ? dev : nil
    }

    private func volumeOf(deviceID: AudioDeviceID) -> Float? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var v: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &v)
        return status == noErr ? v : nil
    }

    private func muteOf(deviceID: AudioDeviceID) -> Bool? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &m)
        guard status == noErr else { return nil }
        return m != 0
    }

    /// Installe un listener CoreAudio sur le volume (pour rester sync si
    /// l'utilisateur change le volume depuis le menubar / Réglages).
    private func installListener() {
        guard !listenerSetup, let dev = defaultOutputDeviceID() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in VolumeManager.shared.refresh() }
        }
        let status = AudioObjectAddPropertyListenerBlock(dev, &addr, .main, block)
        if status == noErr { listenerSetup = true }
    }
}
