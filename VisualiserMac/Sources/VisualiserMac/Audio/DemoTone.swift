import Foundation
import AVFoundation

/// Demo tone — synthesized audio so the visualizer has something to react to
/// when the user can't share screen audio. A bass kick on a steady BPM plus a
/// sweeping sawtooth pad. Output goes through the same ring buffer as real audio.
final class DemoTone {
    private let engine = AVAudioEngine()
    private var isRunning = false

    private var padOsc: AVAudioSourceNode?
    private var subOsc: AVAudioSourceNode?
    private var phasePad: Double = 0
    private var phaseSub: Double = 0
    private var kickPhase: Double = 0
    private var kickEnv: Double = 0
    private var nextKickTime: Double = 0
    private var sampleTime: Double = 0

    let bpm: Double = 124

    func start(into ringBuffer: AudioRingBuffer) throws {
        guard !isRunning else { return }

        let format = AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channels: 1
        )!

        let padNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let twoPi = 2.0 * .pi
            let padFreq: Double = 110.0
            let padFreqMod: Double = 220.0
            let sweepHz = 0.18
            for frame in 0..<Int(frameCount) {
                let t = self.sampleTime + Double(frame) / 48000.0
                let modFreq = padFreq + padFreqMod * sin(t * twoPi * sweepHz)
                self.phasePad += twoPi * modFreq / 48000.0
                if self.phasePad > twoPi { self.phasePad -= twoPi }
                let s = sin(self.phasePad) * 0.18
                abl[0].mData!.assumingMemoryBound(to: Float.self)[frame] = Float(s)
            }
            self.sampleTime += Double(frameCount) / 48000.0
            return noErr
        }

        let subNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let twoPi = 2.0 * .pi
            // schedule kicks
            let interval = 60.0 / self.bpm
            for frame in 0..<Int(frameCount) {
                let t = self.sampleTime + Double(frame) / 48000.0
                while self.nextKickTime > 0 && t >= self.nextKickTime && t - self.nextKickTime < interval * 1.5 {
                    // start a kick envelope
                    self.kickEnv = 1.0
                    self.kickPhase = 0
                    self.nextKickTime += interval
                }
                if self.nextKickTime == 0 { self.nextKickTime = t + 0.5 }

                // bass pitch sweep
                let pitch = 110.0 * exp(-self.kickPhase * 14.0)
                self.phaseSub += twoPi * pitch / 48000.0
                if self.phaseSub > twoPi { self.phaseSub -= twoPi }
                let kickSample = sin(self.phaseSub) * self.kickEnv
                self.kickPhase += 1.0 / 48000.0
                self.kickEnv *= exp(-self.kickPhase * 6.0)
                if self.kickEnv < 0.0001 { self.kickEnv = 0 }

                abl[0].mData!.assumingMemoryBound(to: Float.self)[frame] = Float(kickSample)
            }
            return noErr
        }

        engine.attach(padNode)
        engine.attach(subNode)
        engine.connect(padNode, to: engine.mainMixerNode, format: format)
        engine.connect(subNode, to: engine.mainMixerNode, format: format)

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let floatData = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            floatData[0].withMemoryRebound(to: Float.self, capacity: count) { ptr in
                ringBuffer.write(ptr, count: count)
            }
        }

        engine.prepare()
        try engine.start()
        padOsc = padNode
        subOsc = subNode
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        padOsc = nil
        subOsc = nil
    }
}