import Foundation
import CoreAudio
import AudioToolbox

/// Captures system audio with a Core Audio process tap (macOS 14.2+).
/// Unlike ScreenCaptureKit this only needs the "System Audio Recording"
/// permission, not full screen recording. macOS prompts the first time the
/// tap starts delivering audio.
///
/// Pipeline: global stereo tap -> private aggregate device (default output +
/// tap) -> IOProc on our queue -> mono downmix -> ring buffer.
final class SystemAudioCapture {
    private let ringBuffer: AudioRingBuffer

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "viz.audio.system", qos: .userInteractive)

    /// Preallocated downmix scratch (audio-thread only). IOProc buffers are
    /// far smaller than this in practice; larger ones are truncated.
    private var monoScratch = [Float](repeating: 0, count: 16384)
    private var loggedFormat = false

    var onError: ((String) -> Void)?

    init(ringBuffer: AudioRingBuffer) {
        self.ringBuffer = ringBuffer
    }

    func start() async throws {
        stop()

        // 1. Tap everything the system plays, mixed down to stereo.
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.uuid = UUID()
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(tapDesc, &tapID), "create process tap")

        // 2. Wrap the tap in a private aggregate device clocked by the default output.
        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AUDIVANE System Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapDesc.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &aggregateID),
                  "create aggregate device")

        if let fmt = try? Self.tapFormat(tapID) {
            NSLog("[TAP] format: rate=\(fmt.mSampleRate) ch=\(fmt.mChannelsPerFrame) bits=\(fmt.mBitsPerChannel)")
        }

        // 3. Pull buffers on our own queue.
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) {
            [weak self] _, inInputData, _, _, _ in
            self?.handle(inInputData)
        }, "create IOProc")

        try check(AudioDeviceStart(aggregateID, ioProcID), "start device")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    // MARK: - Audio thread

    private func handle(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let firstData = first.mData else { return }

        if !loggedFormat {
            loggedFormat = true
            NSLog("[TAP] buffers=\(buffers.count) ch/buffer=\(first.mNumberChannels) bytes=\(first.mDataByteSize)")
        }

        if buffers.count == 1 {
            // Interleaved (or mono) Float32.
            let channels = max(1, Int(first.mNumberChannels))
            let frames = min(monoScratch.count,
                             Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            guard frames > 0 else { return }
            let src = firstData.assumingMemoryBound(to: Float.self)
            let inv = 1 / Float(channels)
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += src[i * channels + c] }
                monoScratch[i] = sum * inv
            }
            write(frames)
        } else {
            // Non-interleaved: one buffer per channel.
            let frames = min(monoScratch.count, Int(first.mDataByteSize) / MemoryLayout<Float>.size)
            guard frames > 0 else { return }
            for i in 0..<frames { monoScratch[i] = 0 }
            var used = 0
            for buf in buffers {
                guard let data = buf.mData else { continue }
                let src = data.assumingMemoryBound(to: Float.self)
                for i in 0..<frames { monoScratch[i] += src[i] }
                used += 1
            }
            guard used > 0 else { return }
            let inv = 1 / Float(used)
            for i in 0..<frames { monoScratch[i] *= inv }
            write(frames)
        }
    }

    private func write(_ frames: Int) {
        monoScratch.withUnsafeBufferPointer { ptr in
            ringBuffer.write(ptr.baseAddress!, count: frames)
        }
    }

    // MARK: - Helpers

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else {
            stop()
            throw NSError(domain: "SystemAudioCapture", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to \(what) (OSStatus \(status))."])
        }
    }

    private static func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        guard status == noErr else {
            throw NSError(domain: "SystemAudioCapture", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "No default output device."])
        }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &uid)
        guard status == noErr, let uid else {
            throw NSError(domain: "SystemAudioCapture", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not read output device UID."])
        }
        return uid.takeRetainedValue() as String
    }

    private static func tapFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var fmt = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &fmt)
        guard status == noErr else { throw NSError(domain: "SystemAudioCapture", code: Int(status)) }
        return fmt
    }
}
