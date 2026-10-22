import CoreMIDI
import Foundation
import QuartzCore

/// What the person is doing, for the vibescapes to look at.
///
/// The pointer, the keys and the MIDI notes all arrive from different
/// places — the window, the keyboard and the MIDI ports — and the renderer
/// only ever reads them.
///
/// Everything is a plain number or a pair of them, because that is what a
/// shader can be given. The pointer is in the shader's own coordinates, so
/// it survives a change of aspect ratio; the key is a character code; the
/// MIDI values are what the instrument said.
///
/// Nothing that arrives here is ever logged or sent anywhere.
final class InputState: @unchecked Sendable {
    /// The one the app uses. The window writes into it and the renderer
    /// reads from it, and the preview reads it too, so that a vibescape
    /// which reacts to the pointer can be judged in the app itself.
    static let shared = InputState()

    /// One frame's worth of input, read in one go.
    struct Snapshot {
        /// The pointer, in the shader's `p` space: x across the screen, y up
        /// from the middle, the same numbers `screenP()` produces.
        var mouse: CGPoint = .zero
        /// Whether a mouse button is down.
        var mouseDown = false
        /// The last key that was pressed, as its character code. Zero when
        /// nothing has been pressed.
        var key: Float = 0
        /// Whether a key is being held.
        var keyDown = false
        /// The last MIDI note, 0..127, and how hard it was hit, 0..1.
        var midiNote: Float = 0
        var midiVelocity: Float = 0
        /// How many notes are held at once.
        var midiNotes: Float = 0
        /// The last MIDI controller that moved, and where it is, 0..1.
        var midiCC: Float = 0
        var midiCCValue: Float = 0
    }

    /// The lock. The keyboard and the MIDI ports write from other threads;
    /// the renderer reads once a frame.
    private let lock = NSLock()
    private var current = Snapshot()
    /// The notes that are being held, so that letting go of one is not
    /// mistaken for letting go of another.
    private var held: Set<UInt8> = []

    /// Everything, as it is now.
    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    // MARK: - The pointer and the keys

    func setMouse(_ point: CGPoint) {
        lock.lock(); current.mouse = point; lock.unlock()
    }

    func setMouseDown(_ down: Bool) {
        lock.lock(); current.mouseDown = down; lock.unlock()
    }

    /// The key that was pressed, as its character code.
    func pressKey(_ code: Float) {
        lock.lock(); current.key = code; lock.unlock()
    }

    /// Whether a key is being held.
    func pressKeyDown() {
        lock.lock(); current.keyDown = true; lock.unlock()
    }

    func releaseKey() {
        lock.lock(); current.keyDown = false; lock.unlock()
    }

    // MARK: - MIDI

    func noteOn(_ note: UInt8, _ velocity: UInt8) {
        // A note on with no velocity is a note off, which some keyboards
        // send to be tidy.
        guard velocity > 0 else { noteOff(note); return }
        lock.lock()
        current.midiNote = Float(note)
        current.midiVelocity = Float(velocity) / 127
        held.insert(note)
        current.midiNotes = Float(held.count)
        lock.unlock()
    }

    func noteOff(_ note: UInt8) {
        lock.lock()
        held.remove(note)
        current.midiNotes = Float(held.count)
        lock.unlock()
    }

    func controlChange(_ controller: UInt8, _ value: UInt8) {
        lock.lock()
        current.midiCC = Float(controller)
        current.midiCCValue = Float(value) / 127
        lock.unlock()
    }
}

// The one CoreMIDI call that is not declared by this SDK.
//
// The SDK on this machine ships CoreMIDI without `MIDIClient.h`, so the
// modern source API — `MIDIClientGetNumberOfSources`, `MIDIClientGetSource`,
// `MIDIClientConnectInput`, `MIDIPortSetInputCallback` — is not declared
// and not in the framework's exported symbols either. The API that is
// declared is the older packet one, and it is the one this uses: it reads
// the same MIDI 1.0 messages, from the same sources, and it is the half of
// CoreMIDI that every Mac has always had.
//
// The reading function is declared here rather than called through the
// SDK's own declaration because the SDK marks it deprecated in favour of
// the packet API that is missing, and the missing one cannot be called.
private typealias MidiReadProc = @convention(c) (UnsafePointer<MIDIPacketList>,
                                                  UnsafeMutableRawPointer?,
                                                  UnsafeMutableRawPointer?) -> Void

@_silgen_name("MIDIInputPortCreate")
private func midiInputPortCreate(_ client: MIDIClientRef, _ portName: CFString,
                                 _ readProc: MidiReadProc, _ refCon: UnsafeMutableRawPointer?,
                                 _ outPort: UnsafeMutablePointer<MIDIPortRef>) -> OSStatus

/// Listens to the MIDI ports.
///
/// A port is opened for every source the system knows about, and one is
/// opened for anything plugged in later. There is no permission prompt:
/// reading MIDI is not a privacy permission on macOS the way the
/// microphone is.
final class MidiListener: @unchecked Sendable {
    /// How much room a packet takes: a two-byte length and 256 bytes.
    private static let packetSize = 258

    private let state: InputState
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    /// The sources that are connected, so a new one can be connected and
    /// a gone one dropped.
    private var sources: Set<MIDIEndpointRef> = []
    private var timer: Timer?

    init(state: InputState) {
        self.state = state
    }

    /// Starts listening.
    func start() {
        guard client == 0 else { return }
        var theClient = MIDIClientRef()
        guard MIDIClientCreate("Vibresia" as CFString, nil, nil, &theClient) == noErr else { return }
        client = theClient

        // One port, and every source plugged into it.
        var thePort = MIDIPortRef()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let readProc: MidiReadProc = { packetList, refCon, _ in
            guard let refCon else { return }
            Unmanaged<MidiListener>.fromOpaque(refCon)
                .takeUnretainedValue()
                .read(packetList)
        }
        guard midiInputPortCreate(client, "Vibresia Input" as CFString, readProc, context, &thePort) == noErr else { return }
        port = thePort

        rescan()

        // A MIDI keyboard can be plugged in at any time, and the system
        // does not always say so, so the sources are looked at again
        // every couple of seconds.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.rescan()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Connects the sources that are new and drops the ones that are gone.
    private func rescan() {
        var now: Set<MIDIEndpointRef> = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            if source != 0 { now.insert(source) }
        }
        for source in now.subtracting(sources) {
            MIDIPortConnectSource(port, source, nil)
        }
        for source in sources.subtracting(now) {
            MIDIPortDisconnectSource(port, source)
        }
        sources = now
    }

    /// Reads the packets and turns them into notes.
    ///
    /// A packet list is a fixed-size array of packets rather than a
    /// collection of them, so it is read as the bytes it is: a two-byte
    /// length followed by that many bytes of message, packet after packet.
    fileprivate func read(_ packetList: UnsafePointer<MIDIPacketList>) {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: packetList.pointee.packet) { raw in
            guard let base = raw.baseAddress else { return }
            for index in 0..<Int(packetList.pointee.numPackets) {
                let packet = base.advanced(by: index * Self.packetSize)
                let length = Int(packet.loadUnaligned(as: UInt16.self))
                guard length > 0 else { continue }
                let data = packet.advanced(by: 2)
                for byte in 0..<min(length, 256) {
                    bytes.append(data.loadUnaligned(as: UInt8.self))
                }
            }
        }
        guard !bytes.isEmpty else { return }

        var index = 0
        var status: UInt8 = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte & 0x80 != 0 {
                // A status byte. The channel it is on does not matter here,
                // but running status — where the status byte is left out
                // of the messages that follow it — does, so it is kept.
                status = byte
                index += 1
                continue
            }
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            switch status & 0xF0 {
            case 0x90:
                let note = bytes[index]
                index += 2
                state.noteOn(note, next)
            case 0x80:
                let note = bytes[index]
                index += 2
                state.noteOff(note)
            case 0xB0:
                let controller = bytes[index]
                index += 2
                state.controlChange(controller, next)
            default:
                index += 1
            }
        }
    }
}
