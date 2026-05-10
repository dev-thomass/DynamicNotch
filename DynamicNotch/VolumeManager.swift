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

    /// Définit le volume sur l'output par défaut.
    ///
    /// Trois stratégies essayées en cascade — beaucoup de devices Bluetooth
    /// / AirPlay / DAC USB ne supportent pas l'écriture sur le main element,
    /// il faut alors écrire sur chaque canal individuellement.
    func setVolume(_ newValue: Float) {
        let clamped = min(Float(1), max(Float(0), newValue))
        guard let dev = defaultOutputDeviceID() else { return }

        // 1. Master element (`kAudioObjectPropertyElementMain`) — la
        //    voie royale, marche sur les built-in speakers et la plupart
        //    des devices natifs.
        if writeVolume(deviceID: dev, channel: kAudioObjectPropertyElementMain, value: clamped) {
            level = clamped
            return
        }

        // 2. Per-channel : iterate sur tous les canaux output (typiquement
        //    1=L, 2=R) et écrit chacun à la même valeur. Marche sur les
        //    devices Bluetooth/USB qui exposent le volume par canal sans
        //    main writable.
        var anySuccess = false
        for channel in channels(deviceID: dev) {
            if writeVolume(deviceID: dev, channel: channel, value: clamped) {
                anySuccess = true
            }
        }
        if anySuccess {
            level = clamped
            return
        }

        Log.app.error("VolumeManager.setVolume(\(clamped, privacy: .public)) a échoué sur tous les canaux du device")
    }

    /// Écrit la valeur de volume sur un (device, channel) précis. Retourne
    /// `true` si CoreAudio a accepté.
    private func writeVolume(deviceID: AudioDeviceID, channel: UInt32, value: Float) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        // Vérifier d'abord que la propriété est settable, sinon CoreAudio
        // peut renvoyer noErr en silence sans rien faire (cas Bluetooth).
        var settable: DarwinBoolean = false
        let canStatus = AudioObjectIsPropertySettable(deviceID, &addr, &settable)
        guard canStatus == noErr, settable.boolValue else { return false }
        var v = value
        let status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil,
                                                UInt32(MemoryLayout<Float>.size), &v)
        return status == noErr
    }

    /// Liste les éléments output (canaux) du device. Utilisé pour le
    /// fallback per-channel quand le main element n'est pas writable.
    private func channels(deviceID: AudioDeviceID) -> [UInt32] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyOwnedObjects,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        // Approche naïve : essaie les 8 premiers canaux output (largement
        // suffisant pour 99 % des devices). Plus robuste qu'introspecter
        // l'arbre des sub-objects, et négligeable en perfs.
        _ = addr
        return [1, 2, 3, 4, 5, 6, 7, 8]
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

    /// Installe les listeners CoreAudio sur le volume ET le mute pour
    /// rester sync quand le système / une autre app change la valeur
    /// (menubar slider, AppleScript, touches média en mode lecture seule).
    /// Ces refresh déclenchent le @Published level/isMuted, qui à leur
    /// tour déclenchent le HUD via les souscriptions HUDController.
    private func installListener() {
        guard !listenerSetup, let dev = defaultOutputDeviceID() else { return }

        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in VolumeManager.shared.refresh() }
        }

        // Volume scalar — main element (suffit pour les built-in speakers ;
        // pour les devices Bluetooth qui n'exposent que les canaux
        // individuels, on rate cet event mais le polling qui pourrait être
        // ajouté plus tard couvrirait ça).
        var volumeAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectAddPropertyListenerBlock(dev, &volumeAddr, .main, block)

        // Mute toggle.
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectAddPropertyListenerBlock(dev, &muteAddr, .main, block)

        listenerSetup = true
    }
}
