//
//  CoreAudioVolumeControl.swift
//  DynamicNotch
//
//  Volume de la sortie par défaut via le « volume principal virtuel »
//  d'AudioToolbox, celui que macOS utilise : il gère correctement les
//  sorties Bluetooth, AirPlay et USB (l'élément principal CoreAudio non).
//
//  Écouteurs : on utilise l'API à base de `AudioObjectPropertyListenerProc`
//  (pointeur de fonction C), pas `…ListenerBlock`. Un `AudioObjectPropertyListenerBlock`
//  stocké comme closure Swift est re-ponté vers un nouveau bloc Objective-C à
//  chaque appel : `AudioObjectRemovePropertyListenerBlock` ne correspond alors
//  jamais au bloc réellement enregistré et ne retire donc rien (vérifié par
//  une sonde : les écouteurs « retirés » continuaient de se déclencher). Avec
//  un pointeur de fonction C top-level et le même pointeur de « client data »
//  qu'à l'ajout, le retrait fonctionne bien.
//
//  « Client data » : une boîte retenue qui pointe faiblement vers le contrôle,
//  pas le contrôle lui-même. Un rappel déjà posté sur le fil principal quand le
//  contrôle disparaît trouve alors `owner == nil` au lieu d'un pointeur libéré.
//

import AudioToolbox
import CoreAudio

/// Retenue par le contrôle (`passRetained`) et libérée dans son `deinit`, après
/// le retrait de tous les écouteurs. `owner` n'est lu que sur le fil principal.
final class CoreAudioListenerBox: @unchecked Sendable {
    weak var owner: CoreAudioVolumeControl?

    /// Boîte désignée par le « client data » d'un écouteur (non retenue ici :
    /// la référence Swift renvoyée la retient le temps du rappel).
    static func from(_ clientData: UnsafeMutableRawPointer) -> CoreAudioListenerBox {
        Unmanaged<CoreAudioListenerBox>.fromOpaque(clientData).takeUnretainedValue()
    }
}

/// Rappelée par CoreAudio (thread arbitraire) quand la sortie par défaut change.
private func coreAudioDefaultDeviceListenerProc(
    _: AudioObjectID,
    _: UInt32,
    _: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let box = CoreAudioListenerBox.from(clientData)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            box.owner?.handleDefaultDeviceChanged()
        }
    }
    return noErr
}

/// Rappelée par CoreAudio (thread arbitraire) quand le volume ou le muet du
/// périphérique courant change.
private func coreAudioDeviceValueListenerProc(
    _: AudioObjectID,
    _: UInt32,
    _: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let box = CoreAudioListenerBox.from(clientData)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            box.owner?.onVolumeChange?()
        }
    }
    return noErr
}

@MainActor
final class CoreAudioVolumeControl: VolumeControl {
    var onVolumeChange: (() -> Void)?
    var onDeviceChange: (() -> Void)?

    // `nonisolated(unsafe)` : lu depuis `deinit`, qui n'est pas isolé au
    // MainActor. Le retrait des écouteurs n'y a besoin que de cette valeur et
    // de l'API C ; il n'y a pas d'accès concurrent réel puisque `deinit` ne
    // s'exécute qu'une fois, quand plus personne d'autre ne détient `self`.
    private nonisolated(unsafe) var device = AudioDeviceID(kAudioObjectUnknown)

    // `nonisolated` : ce sont des constantes immuables (le type
    // `AudioObjectPropertyAddress` est `Sendable`) lues aussi depuis `deinit`
    // (contexte non isolé) et depuis les procs C au-dessus (également non
    // isolées).
    private nonisolated static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private nonisolated static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private nonisolated static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    /// « Client data » de tous les écouteurs : la `CoreAudioListenerBox`
    /// retenue (mêmes valeurs à l'ajout et au retrait, faute de quoi CoreAudio
    /// ne reconnaît pas l'écouteur). `nonisolated(unsafe)` : constante lue
    /// aussi depuis `deinit`.
    nonisolated(unsafe) let listenerClientData: UnsafeMutableRawPointer

    init() {
        let box = CoreAudioListenerBox()
        listenerClientData = Unmanaged.passRetained(box).toOpaque()
        box.owner = self
        var address = Self.defaultOutputAddress
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &address, coreAudioDefaultDeviceListenerProc, listenerClientData
        )
        attach(to: Self.readDefaultDevice())
    }

    deinit {
        var systemAddress = Self.defaultOutputAddress
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &systemAddress, coreAudioDefaultDeviceListenerProc,
            listenerClientData
        )
        if device != kAudioObjectUnknown {
            var volumeAddr = Self.volumeAddress
            AudioObjectRemovePropertyListener(device, &volumeAddr, coreAudioDeviceValueListenerProc, listenerClientData)
            var muteAddr = Self.muteAddress
            AudioObjectRemovePropertyListener(device, &muteAddr, coreAudioDeviceValueListenerProc, listenerClientData)
        }
        // Plus aucun écouteur : la boîte peut partir (un rappel déjà posté la
        // retient encore et y trouvera `owner == nil`).
        Unmanaged<CoreAudioListenerBox>.fromOpaque(listenerClientData).release()
    }

    var isSettable: Bool {
        var address = Self.volumeAddress
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    var isMuteSettable: Bool {
        var address = Self.muteAddress
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    var level: Double {
        var address = Self.volumeAddress
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard device != kAudioObjectUnknown,
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return 0 }
        return Double(min(1, max(0, value)))
    }

    var isMuted: Bool {
        var address = Self.muteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }

    func setLevel(_ level: Double) {
        guard device != kAudioObjectUnknown else { return }
        var address = Self.volumeAddress
        var value = Float32(min(1, max(0, level)))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    func setMuted(_ muted: Bool) {
        guard device != kAudioObjectUnknown else { return }
        var address = Self.muteAddress
        guard AudioObjectHasProperty(device, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: écouteurs

    fileprivate func handleDefaultDeviceChanged() {
        attach(to: Self.readDefaultDevice())
        onDeviceChange?()
    }

    /// Rebranche les écouteurs volume et muet sur `newDevice`. Ne fait rien si
    /// `newDevice` est déjà le périphérique courant (évite d'empiler des
    /// écouteurs à chaque notification de sortie par défaut).
    private func attach(to newDevice: AudioDeviceID) {
        guard newDevice != device else { return }
        if device != kAudioObjectUnknown {
            removeDeviceListeners(from: device)
        }
        device = newDevice
        guard device != kAudioObjectUnknown else { return }
        addDeviceListeners(to: device)
    }

    private func addDeviceListeners(to device: AudioDeviceID) {
        var volumeAddr = Self.volumeAddress
        if AudioObjectHasProperty(device, &volumeAddr) {
            AudioObjectAddPropertyListener(device, &volumeAddr, coreAudioDeviceValueListenerProc, listenerClientData)
        }
        var muteAddr = Self.muteAddress
        if AudioObjectHasProperty(device, &muteAddr) {
            AudioObjectAddPropertyListener(device, &muteAddr, coreAudioDeviceValueListenerProc, listenerClientData)
        }
    }

    private func removeDeviceListeners(from device: AudioDeviceID) {
        var volumeAddr = Self.volumeAddress
        AudioObjectRemovePropertyListener(device, &volumeAddr, coreAudioDeviceValueListenerProc, listenerClientData)
        var muteAddr = Self.muteAddress
        AudioObjectRemovePropertyListener(device, &muteAddr, coreAudioDeviceValueListenerProc, listenerClientData)
    }

    private static func readDefaultDevice() -> AudioDeviceID {
        var address = defaultOutputAddress
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }
}
