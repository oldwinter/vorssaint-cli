// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import Foundation

// Classic HAL object API for device volume/mute/selection.

enum AudioHAL {
    enum Scope { case output, input
        var prop: AudioObjectPropertyScope { self == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput }
    }

    private static func getProp<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector,
                                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                   element: UInt32 = kAudioObjectPropertyElementMain,
                                   _ out: inout T) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
        var sz = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &out) == noErr
    }

    private static func setProp<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector,
                                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                   element: UInt32 = kAudioObjectPropertyElementMain,
                                   _ value: inout T) -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
        return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }

    static func defaultDevice(_ scope: Scope) -> AudioObjectID? {
        var id = AudioObjectID(0)
        let sel = scope == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
        guard getProp(AudioObjectID(kAudioObjectSystemObject), sel, &id), id != 0 else { return nil }
        return id
    }

    static func setDefaultDevice(_ scope: Scope, _ id: AudioObjectID) -> Bool {
        var id = id
        let sel = scope == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
        return setProp(AudioObjectID(kAudioObjectSystemObject), sel, &id)
    }

    static func volume(_ dev: AudioObjectID, scope: Scope) -> Float? {
        var v = Float32(0)
        return getProp(dev, kAudioDevicePropertyVolumeScalar, scope: scope.prop, &v) ? v : nil
    }

    static func setVolume(_ dev: AudioObjectID, scope: Scope, _ v: Float) -> Bool {
        var v = v
        return setProp(dev, kAudioDevicePropertyVolumeScalar, scope: scope.prop, &v)
    }

    static func muted(_ dev: AudioObjectID, scope: Scope) -> Bool? {
        var m = UInt32(0)
        return getProp(dev, kAudioDevicePropertyMute, scope: scope.prop, &m) ? m != 0 : nil
    }

    static func setMuted(_ dev: AudioObjectID, scope: Scope, _ m: Bool) -> Bool {
        var m: UInt32 = m ? 1 : 0
        return setProp(dev, kAudioDevicePropertyMute, scope: scope.prop, &m)
    }

    static func name(_ dev: AudioObjectID) -> String {
        var cf: CFString = "" as CFString
        return getProp(dev, kAudioDevicePropertyDeviceNameCFString, &cf) ? cf as String : "device \(dev)"
    }

    static func uid(_ dev: AudioObjectID) -> String {
        var cf: CFString = "" as CFString
        return getProp(dev, kAudioDevicePropertyDeviceUID, &cf) ? cf as String : ""
    }

    struct Device: Encodable {
        var id: UInt32, name: String, uid: String
        var isOutput: Bool, isInput: Bool, isDefaultOutput: Bool, isDefaultInput: Bool
    }

    static func devices() -> [Device] {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                         mScope: kAudioObjectPropertyScopeGlobal,
                                         mElement: kAudioObjectPropertyElementMain)
        var sz = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(sz) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &sz, &ids) == noErr else { return [] }
        let defOut = defaultDevice(.output), defIn = defaultDevice(.input)
        return ids.map { id in
            Device(id: id, name: name(id), uid: uid(id),
                   isOutput: streamCount(id, .output) > 0, isInput: streamCount(id, .input) > 0,
                   isDefaultOutput: id == defOut, isDefaultInput: id == defIn)
        }
    }

    private static func streamCount(_ dev: AudioObjectID, _ scope: Scope) -> Int {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                         mScope: scope.prop, mElement: kAudioObjectPropertyElementMain)
        var sz = UInt32(0)
        guard AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &sz) == noErr else { return 0 }
        return Int(sz) / MemoryLayout<AudioStreamID>.size
    }

    static func findDevice(_ query: String, scope: Scope) -> AudioObjectID? {
        let all = devices().filter { scope == .output ? $0.isOutput : $0.isInput }
        if let exact = all.first(where: { $0.uid == query || String($0.id) == query }) { return AudioObjectID(exact.id) }
        let q = query.lowercased()
        return all.first(where: { $0.name.lowercased().contains(q) }).map { AudioObjectID($0.id) }
    }
}
