import AVFoundation
import Foundation

/// Saves the last few bars of a vibescape, with the music, as a movie.
///
/// The picture is the app's own renderer: the same draw the window is doing,
/// over the last stretch of its clock, so it is the vibescape rather
/// than a picture of it. The sound is what the app was hearing — the music,
/// as it was.
///
/// Three files and a merge, because that is what AVFoundation makes easy:
/// the picture goes into a movie, the sound into an audio file, and the two
/// are put together at the end.
enum VideoExporter {
    /// The frames a second.
    static let fps: Double = 30
    /// The size of the movie.
    static let width = 1280
    static let height = 720

    /// How long a clip is: a number of bars of the music.
    ///
    /// Bars rather than seconds, because a bar is what the music is in. Eight
    /// bars is sixteen seconds at 120bpm, which is a long recording of
    /// anything; four is eight, which is short. So the count follows the
    /// tempo — whichever of the two lands closest to ten seconds — and the
    /// share sheet says which it chose.
    struct Clip: Equatable {
        /// How many bars. Zero when there is no tempo to count them in.
        let bars: Int
        /// How long that is, in seconds.
        let seconds: Double

        /// The clip for a tempo.
        ///
        /// A tempo of zero means there is nothing to count bars in — nothing
        /// is playing, or the beat has been lost — and then ten seconds is the
        /// best answer there is.
        static func forTempo(_ bpm: Double) -> Clip {
            guard bpm > 20 else { return Clip(bars: 0, seconds: 10) }
            let bar = 4 * (60.0 / bpm)
            let candidates = [4, 8].map { Clip(bars: $0, seconds: Double($0) * bar) }
            return candidates.min(by: { abs($0.seconds - 10) < abs($1.seconds - 10) }) ?? candidates[0]
        }

        /// How it is described, for the button's tooltip.
        var description: String {
            bars == 0
                ? "the last \(Int(seconds.rounded())) seconds"
                : "the last \(bars) bar\(bars == 1 ? "" : "s") (\(Int(seconds.rounded())) seconds)"
        }
    }

    enum ExportError: LocalizedError {
        case noAudio
        case noFrames
        case couldNotWrite(String)

        var errorDescription: String? {
            switch self {
            case .noAudio:
                return "There was no sound to record — the app has not been listening."
            case .noFrames:
                return "The vibescape didn't draw."
            case .couldNotWrite(let why):
                return "Couldn't write the movie: \(why)"
            }
        }
    }

    /// Records the clip and writes it to `url`.
    static func export(renderer: OpenGLRenderer, mode: VibescapeID,
                       audio: AudioEngine, clip: Clip, to url: URL) async throws {
        // The sound: the last of it, straight out of the ring buffer the app
        // has been filling — as much of it as there is. A clip is as long as
        // the music the app has actually heard, so a recording made a moment
        // after launch is a short one rather than a broken one.
        guard let sound = audio.recentAudio(upTo: clip.seconds) else {
            throw ExportError.noAudio
        }
        // The picture is as long as the sound, so the two line up.
        let length = Double(sound.frameLength) / sound.format.sampleRate

        // The picture: the same stretch of the vibescape, re-drawn. The
        // render is a GPU job, so it happens off the main thread.
        let frames = await withCheckedContinuation { continuation in
            var images: [CGImage] = []
            let count = max(1, Int(length * fps))
            let start = renderer.animationTime - length
            renderer.renderImages(width: width, height: height, mode: mode,
                                  frames: count, fps: fps, startTime: start) { _, image in
                images.append(image)
            }
            continuation.resume(returning: images)
        }
        guard !frames.isEmpty else { throw ExportError.noFrames }

        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vibresia-video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let movie = work.appendingPathComponent("picture.mov")
        let track = work.appendingPathComponent("sound.m4a")

        do { try writeAudio(sound, to: track) } catch {
            throw ExportError.couldNotWrite("the sound: \(error.localizedDescription)")
        }
        do { try await writeVideo(frames, to: movie) } catch {
            throw ExportError.couldNotWrite("the picture: \(error.localizedDescription)")
        }
        do { try await merge(video: movie, audio: track, to: url) } catch {
            throw ExportError.couldNotWrite("the two together: \(error.localizedDescription)")
        }
    }

    // MARK: - The sound

    /// The sound, as an audio file.
    ///
    /// AVFoundation writes the AAC itself, which is the one part of this
    /// that would be a pile of buffer plumbing by hand.
    private static func writeAudio(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVEncoderBitRateKey: 128_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    // MARK: - The picture

    /// The frames, as a movie.
    private static func writeVideo(_ frames: [CGImage], to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoMaxKeyFrameIntervalKey: Int(fps),
            ],
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for (index, image) in frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard let buffer = pixelBuffer(from: image) else { continue }
            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            if !adaptor.append(buffer, withPresentationTime: time) {
                throw ExportError.couldNotWrite(writer.error?.localizedDescription ?? "unknown")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw ExportError.couldNotWrite(writer.error?.localizedDescription ?? "unknown")
        }
    }

    /// An image as a pixel buffer, which is what the writer takes.
    private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height,
                                  kCVPixelFormatType_32ARGB, attributes as CFDictionary,
                                  &buffer) == kCVReturnSuccess, let buffer else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width, height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    // MARK: - The two together

    /// The picture and the sound, as one movie.
    private static func merge(video: URL, audio: URL, to output: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)

        guard let videoSource = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioSource = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.couldNotWrite("the movie had no picture or no sound")
        }

        let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                     preferredTrackID: kCMPersistentTrackID_Invalid)!
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoAsset.duration),
            of: videoSource, at: .zero)

        let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                     preferredTrackID: kCMPersistentTrackID_Invalid)!
        try audioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: audioAsset.duration),
            of: audioSource, at: .zero)

        guard let exporter = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.couldNotWrite("the movie could not be put together")
        }
        // The export session refuses to write over a file that is already
        // there, and says so in a way that sounds like a permissions
        // problem: "the requested file name is already in use". Exporting the
        // same vibescape twice hits that, because the first movie is still
        // in Downloads.
        if FileManager.default.fileExists(atPath: output.path) {
            try? FileManager.default.removeItem(at: output)
        }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously { continuation.resume() }
        }
        if exporter.status != .completed {
            throw ExportError.couldNotWrite(exporter.error?.localizedDescription ?? "unknown")
        }
    }
}
