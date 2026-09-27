//
//  CoreAudioVolumeControl.swift
//  DynamicNotch
//
//  Volume de la sortie par défaut via le « volume principal virtuel »
//  d'AudioToolbox, celui que macOS utilise : il gère correctement les
//  sorties Bluetooth, AirPlay et USB (l'élément principal CoreAudio non).
//

import AudioToolbox
import CoreAudio

@MainActor
final class CoreAudioVolumeControl: VolumeControl {
    var onVolumeChange: (() -> Void)?
    var onDeviceChange: (() -> Void)?

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var valueListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volume = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var mute = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.attach(to: Self.readDefaultDevice())
                self.onDeviceChange?()
            }
        }
        deviceListener = listener
        var address = Self.defaultOutput
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        attach(to: Self.readDefaultDevice())
    }

    var isSettable: Bool {
        var address = Self.volume
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    var level: Double {
        var address = Self.volume
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard device != kAudioObjectUnknown,
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return 0 }
        return Double(min(1, max(0, value)))
    }

    var isMuted: Bool {
        var address = Self.mute
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }

    func setLevel(_ level: Double) {
        var address = Self.volume
        var value = Float32(min(1, max(0, level)))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    func setMuted(_ muted: Bool) {
        var address = Self.mute
        guard AudioObjectHasProperty(device, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: écouteurs

    /// Rebranche les écouteurs volume et muet sur `newDevice`.
    private func attach(to newDevice: AudioDeviceID) {
        if let valueListener, device != kAudioObjectUnknown {
            var volume = Self.volume
            var mute = Self.mute
            AudioObjectRemovePropertyListenerBlock(device, &volume, .main, valueListener)
            AudioObjectRemovePropertyListenerBlock(device, &mute, .main, valueListener)
        }
        device = newDevice
        guard device != kAudioObjectUnknown else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onVolumeChange?() }
        }
        valueListener = listener
        var volume = Self.volume
        var mute = Self.mute
        AudioObjectAddPropertyListenerBlock(device, &volume, .main, listener)
        if AudioObjectHasProperty(device, &mute) {
            AudioObjectAddPropertyListenerBlock(device, &mute, .main, listener)
        }
    }

    private static func readDefaultDevice() -> AudioDeviceID {
        var address = defaultOutput
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }
}
