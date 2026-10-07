//
//  MixerEngine.swift
//  boringNotch
//
//  Per-app volume mixer engine. For one app: a muted CoreAudio process
//  tap removes the app's sound from the original output, and a private
//  aggregate device re-renders the tapped stream with the chosen gain.
//  CoreAudio mixes our aggregate client with every untouched app.
//
//  Adapted from Vorssaint (github.com/vorssaint/vorssaint-utils),
//  GPL-3.0-or-later, and the aggregate recipe from insidegui/AudioCap
//  (BSD-2-Clause). Apps left at 100% are never tapped.
//

import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

enum MixerCoreAudioError: LocalizedError {
    case osStatus(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case .osStatus(let status, let operation):
            return "\(operation) failed with status \(status)"
        }
    }
}

enum MixerCoreAudio {
    static func defaultOutputDevice() throws -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0, nil, &size, &device
        )
        guard status == noErr else { throw MixerCoreAudioError.osStatus(status, "default output device") }
        return device
    }

    static func deviceUID(_ device: AudioDeviceID) throws -> String {
        guard let uid = readString(device, kAudioDevicePropertyDeviceUID) else {
            throw MixerCoreAudioError.osStatus(-1, "device UID")
        }
        return uid
    }

    static func processList() throws -> [AudioObjectID] {
        var size = UInt32(0)
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0, nil, &size
        )
        guard status == noErr else { throw MixerCoreAudioError.osStatus(status, "process list size") }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0, nil, &size, &list
        )
        guard status == noErr else { throw MixerCoreAudioError.osStatus(status, "process list") }
        return list
    }

    static func pid(of process: AudioObjectID) -> pid_t? {
        read(process, kAudioProcessPropertyPID, as: pid_t.self)
    }

    static func bundleID(of process: AudioObjectID) -> String? {
        readString(process, kAudioProcessPropertyBundleID)
    }

    static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        read(process, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
    }

    @available(macOS 14.2, *)
    static func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = address(kAudioTapPropertyFormat)
        let status = AudioObjectGetPropertyData(
            tap,
            &addr,
            0, nil, &size, &format
        )
        guard status == noErr else { throw MixerCoreAudioError.osStatus(status, "tap format") }
        return format
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as type: T.Type) -> T? {
        var value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        var addr = address(selector)
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, value)
        guard status == noErr else { return nil }
        return value.pointee
    }

    private static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr else { return nil }
        var value: Unmanaged<CFString>?
        var mutableSize = size
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &mutableSize, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// Shared, lock-free render state. The engine writes the gain from the
/// main thread; the audio thread only reads it.
final class MixerRenderState {
    let tapChannels: Int
    var gain: Float

    init(tapChannels: Int, gain: Float) {
        self.tapChannels = tapChannels
        self.gain = gain
    }

    /// Which input buffer carries the tap: the last buffer whose shape the
    /// tap announced (an aggregate may present the device's own microphone
    /// input ahead of the tap). Adapted from Vorssaint MixerRender.
    static func tapBufferIndex(in buffers: UnsafeMutableAudioBufferListPointer, tapChannels: Int) -> Int? {
        var lone: Int?
        for index in stride(from: buffers.count - 1, through: 0, by: -1)
        where buffers[index].mData != nil && buffers[index].mNumberChannels > 0 {
            if Int(buffers[index].mNumberChannels) == tapChannels { return index }
            if buffers.count == 1 { lone = index }
        }
        return lone
    }

    /// Renders one interleaved source buffer onto the output scaled by gain
    /// and silences whatever it does not write. Adapted from Vorssaint
    /// MixerRender (handles mono folding and channel mapping).
    static func render(source: AudioBuffer, into output: UnsafeMutableAudioBufferListPointer, gain: Float) {
        var written = 0
        defer { silence(output, from: written) }

        let sourceChannels = Int(source.mNumberChannels)
        guard sourceChannels > 0,
              let samples = source.mData?.assumingMemoryBound(to: Float.self) else { return }

        var frames = frames(bytes: source.mDataByteSize, channels: source.mNumberChannels)
        var outputChannels = 0
        for buffer in output where buffer.mNumberChannels > 0 {
            outputChannels += Int(buffer.mNumberChannels)
            guard buffer.mData != nil else { continue }
            frames = min(frames, self.frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels))
        }
        guard frames > 0, outputChannels > 0 else { return }

        if output.count == 1, Int(output[0].mNumberChannels) == sourceChannels,
           let destination = output[0].mData?.assumingMemoryBound(to: Float.self) {
            var gainValue = gain
            vDSP_vsmul(samples, 1, &gainValue, destination, 1, vDSP_Length(frames * sourceChannels))
            written = frames
            return
        }

        if outputChannels == 1, sourceChannels > 1 {
            guard let buffer = output.first(where: { $0.mNumberChannels == 1 && $0.mData != nil }),
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
            var scale = gain / Float(sourceChannels)
            vDSP_vsmul(samples, vDSP_Stride(sourceChannels), &scale, destination, 1, vDSP_Length(frames))
            for channel in 1..<sourceChannels {
                vDSP_vsma(samples + channel, vDSP_Stride(sourceChannels), &scale,
                          destination, 1, destination, 1, vDSP_Length(frames))
            }
            written = frames
            return
        }

        var firstOutputChannel = 0
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            defer { firstOutputChannel += channels }
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for channel in 0..<channels {
                let outputIndex = firstOutputChannel + channel
                guard outputIndex < sourceChannels else {
                    vDSP_vclr(destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
                    continue
                }
                var gainValue = gain
                vDSP_vsmul(samples + outputIndex, vDSP_Stride(sourceChannels), &gainValue,
                           destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
            }
        }
        written = frames
    }

    static func silence(_ output: UnsafeMutableAudioBufferListPointer, from frame: Int = 0) {
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0,
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let unwritten = frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels) - frame
            guard unwritten > 0 else { continue }
            vDSP_vclr(destination + frame * channels, 1, vDSP_Length(unwritten * channels))
        }
    }

    private static func frames(bytes: UInt32, channels: UInt32) -> Int {
        guard channels > 0 else { return 0 }
        return Int(bytes) / (MemoryLayout<Float>.size * Int(channels))
    }
}

/// One app's tap plus aggregate device, running until stopped.
final class MixerEngine {
    let processObjectID: AudioObjectID
    private let state: MixerRenderState
    private let queue = DispatchQueue(label: "notch.mixer.render", qos: .userInteractive)

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var running = false

    init(processObjectID: AudioObjectID, gain: Float) throws {
        guard #available(macOS 14.2, *) else {
            throw MixerCoreAudioError.osStatus(-1, "process taps need macOS 14.2 or newer")
        }

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .mutedWhenTapped

        var createdTap = AudioObjectID(0)
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &createdTap)
        guard tapStatus == noErr else { throw MixerCoreAudioError.osStatus(tapStatus, "create process tap") }

        var status: OSStatus = noErr
        var keepTap = false
        defer {
            if !keepTap, createdTap != 0 {
                AudioHardwareDestroyProcessTap(createdTap)
            }
        }

        let format = try MixerCoreAudio.tapFormat(createdTap)
        let channels = Int(format.mChannelsPerFrame)

        self.processObjectID = processObjectID
        self.state = MixerRenderState(tapChannels: channels > 0 ? channels : 2, gain: gain)
        self.tapID = createdTap

        let outputDevice = try MixerCoreAudio.defaultOutputDevice()
        let outputUID = try MixerCoreAudio.deviceUID(outputDevice)

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchMixer-\(processObjectID)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        var createdAggregate = AudioObjectID(0)
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &createdAggregate)
        guard status == noErr else { throw MixerCoreAudioError.osStatus(status, "create aggregate device") }
        aggregateID = createdAggregate
        keepTap = true
    }

    func start() throws {
        guard !running else { return }
        let state = self.state

        var createdIOProc: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcIDWithBlock(&createdIOProc, aggregateID, queue) {
            _, inInputData, _, outOutputData, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let output = UnsafeMutableAudioBufferListPointer(outOutputData)
            guard let index = MixerRenderState.tapBufferIndex(in: input, tapChannels: state.tapChannels) else {
                MixerRenderState.silence(output)
                return
            }
            MixerRenderState.render(source: input[index], into: output, gain: state.gain)
        }
        guard status == noErr, let createdIOProc else {
            throw MixerCoreAudioError.osStatus(status, "create IO proc")
        }
        ioProcID = createdIOProc

        status = AudioDeviceStart(aggregateID, createdIOProc)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, createdIOProc)
            ioProcID = nil
            throw MixerCoreAudioError.osStatus(status, "start aggregate device")
        }
        running = true
    }

    func setGain(_ gain: Float) {
        state.gain = gain
    }

    func stop() {
        guard running || tapID != 0 else { return }
        running = false

        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != 0 {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = 0
        }
    }

    deinit {
        stop()
    }
}
