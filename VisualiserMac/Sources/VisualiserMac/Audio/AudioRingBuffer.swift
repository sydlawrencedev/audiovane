import Foundation

/// Lock-free SPSC ring buffer for mono Float32 audio samples.
/// Single producer (audio thread) — single consumer (analyzer thread).
final class AudioRingBuffer {
    private let capacity: Int          // power of two
    private var storage: [Float]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0

    init(seconds: Double = 2.0, sampleRate: Double = 48000) {
        let cap = AudioRingBuffer.nextPowerOfTwo(Int(seconds * sampleRate * 2))
        self.capacity = cap
        self.storage = [Float](repeating: 0, count: cap)
    }

    private static func nextPowerOfTwo(_ n: Int) -> Int {
        var x = max(1, n) - 1
        x |= x >> 1
        x |= x >> 2
        x |= x >> 4
        x |= x >> 8
        x |= x >> 16
        x |= x >> 32
        return x + 1
    }

    /// Called on the producer thread with every write (e.g. instrument detection).
    var onWrite: ((UnsafePointer<Float>, Int) -> Void)?

    /// Producer side (audio thread).
    func write(_ samples: UnsafePointer<Float>, count: Int) {
        onWrite?(samples, count)
        let mask = capacity - 1
        let w = writeIndex
        let base = w & mask
        let firstChunk = min(count, capacity - base)
        storage.withUnsafeMutableBufferPointer { buf in
            guard let baseAddr = buf.baseAddress else { return }
            let dst1 = baseAddr.advanced(by: base)
            memcpy(dst1, samples, firstChunk * MemoryLayout<Float>.size)
            if firstChunk < count {
                let remaining = count - firstChunk
                let dst2 = baseAddr
                memcpy(dst2, samples.advanced(by: firstChunk), remaining * MemoryLayout<Float>.size)
            }
        }
        writeIndex = w + count
    }

    /// Consumer side (analyzer thread).
    func read(into dest: UnsafeMutablePointer<Float>, count: Int) -> Bool {
        let avail = writeIndex - readIndex
        guard avail >= count else { return false }
        let mask = capacity - 1
        let r = readIndex
        let base = r & mask
        let firstChunk = min(count, capacity - base)
        storage.withUnsafeBufferPointer { buf in
            guard let baseAddr = buf.baseAddress else { return }
            let src1 = baseAddr.advanced(by: base)
            for i in 0..<firstChunk {
                dest[i] = src1[i]
            }
            if firstChunk < count {
                let src2 = baseAddr
                for i in firstChunk..<count {
                    dest[i] = src2[i - firstChunk]
                }
            }
        }
        readIndex = r + count
        return true
    }

    /// Copies the newest `count` samples without waiting for `count` fresh
    /// ones, and marks everything as consumed. Used for overlapping FFT windows.
    func readLatest(into dest: UnsafeMutablePointer<Float>, count: Int) -> Bool {
        let w = writeIndex
        guard w >= count, count <= capacity else { return false }
        let mask = capacity - 1
        let base = (w - count) & mask
        let firstChunk = min(count, capacity - base)
        storage.withUnsafeBufferPointer { buf in
            guard let baseAddr = buf.baseAddress else { return }
            memcpy(dest, baseAddr.advanced(by: base), firstChunk * MemoryLayout<Float>.size)
            if firstChunk < count {
                memcpy(dest.advanced(by: firstChunk), baseAddr, (count - firstChunk) * MemoryLayout<Float>.size)
            }
        }
        readIndex = w
        return true
    }

    /// Reads up to `count` of the newest samples, and says how many it got.
    ///
    /// `readLatest` wants the whole window and refuses if it isn't there yet.
    /// A recording wants whatever has been captured: ten seconds of music if
    /// there has been ten seconds of music, and what there is if there isn't.
    func readLatestAvailable(into dest: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let w = writeIndex
        guard w > 0 else { return 0 }
        let wanted = min(count, w)
        let mask = capacity - 1
        let base = (w - wanted) & mask
        let firstChunk = min(wanted, capacity - base)
        storage.withUnsafeBufferPointer { buf in
            let src1 = buf.baseAddress! + base
            for i in 0..<firstChunk {
                dest[i] = src1[i]
            }
            if firstChunk < wanted {
                let src2 = buf.baseAddress!
                for i in firstChunk..<wanted {
                    dest[i] = src2[i - firstChunk]
                }
            }
        }
        readIndex = w
        return wanted
    }

    /// Total samples ever written: an audio-time clock for the consumer.
    var totalWritten: Int { writeIndex }

    func available() -> Int {
        return writeIndex - readIndex
    }

    func reset() {
        writeIndex = 0
        readIndex = 0
        for i in 0..<capacity { storage[i] = 0 }
    }
}