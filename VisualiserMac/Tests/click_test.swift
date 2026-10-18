// Synthetic click test for the header drop-downs.
//
// The app logs the on-screen frame of the mode pill and of every list row
// ("[DD] pill ..." / "[DD] row ..."). This script reads those frames out of
// the app's log and posts real mouse events at them, so the test exercises
// the same hit-testing path a human click does. That matters: an AXPress
// would bypass hit-testing entirely and wouldn't catch a row being covered
// by the click-away catcher.
//
// Usage: swift Tests/click_test.swift [app-dir]
import AppKit
import CoreGraphics
import Foundation

let logPath = "/tmp/click_app.log"

func say(_ s: String) { print(s) }

func click(at point: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    // A little movement first so the app sees the pointer arrive.
    let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                       mouseCursorPosition: point, mouseButton: .left)
    move?.post(tap: .cghidEventTap)
    usleep(120_000)
    for type in [CGEventType.leftMouseDown, CGEventType.leftMouseUp] {
        let e = CGEvent(mouseEventSource: src, mouseType: type,
                        mouseCursorPosition: point, mouseButton: .left)
        e?.post(tap: .cghidEventTap)
        usleep(70_000)
    }
    usleep(350_000)
}

/// Parse "[DD] pill mode frame (x, y, w, h)" out of the app log.
func frameFrom(log text: String, kind: String, key: String) -> CGRect? {
    for line in text.split(separator: "\n") {
        let s = String(line)
        guard s.contains("[DD] \(kind)") && s.contains(key) else { continue }
        guard let open = s.range(of: "frame (") else { continue }
        let rest = s[open.upperBound...]
        guard let close = rest.firstIndex(of: ")") else { continue }
        let nums = rest[..<close].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if nums.count == 4 {
            return CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
        }
    }
    return nil
}

func readLog() -> String {
    (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
}

// ---- launch the app ----
let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
try? FileManager.default.removeItem(atPath: logPath)
FileManager.default.createFile(atPath: logPath, contents: nil)

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "\(dir)/build/VisualiserMac.app/Contents/MacOS/VisualiserMac")
if let out = FileHandle(forWritingAtPath: logPath) {
    proc.standardOutput = out
    proc.standardError = out
}
try! proc.run()
defer { proc.terminate() }

Thread.sleep(forTimeInterval: 4.0)
NSApp.activate(ignoringOtherApps: true)
Thread.sleep(forTimeInterval: 1.0)

// The pill is reported once the first layout settles.
var pill = frameFrom(log: readLog(), kind: "pill", key: "mode")
var attempts = 0
while pill == nil && attempts < 20 {
    Thread.sleep(forTimeInterval: 0.25)
    pill = frameFrom(log: readLog(), kind: "pill", key: "mode")
    attempts += 1
}
guard let pillFrame = pill else {
    say("✗ never saw the mode pill frame in the log")
    say(String(readLog().suffix(800)))
    exit(1)
}
say("pill frame: \(pillFrame)")

// Click the pill to open the list.
click(at: CGPoint(x: pillFrame.midX, y: pillFrame.midY))

// Wait for the list rows to be reported.
var row = frameFrom(log: readLog(), kind: "row", key: "CONSTELLATION")
attempts = 0
while row == nil && attempts < 20 {
    Thread.sleep(forTimeInterval: 0.25)
    row = frameFrom(log: readLog(), kind: "row", key: "CONSTELLATION")
    attempts += 1
}
guard let rowFrame = row else {
    say("✗ list never opened — the row frames were never reported")
    say(String(readLog().suffix(800)))
    exit(2)
}
say("row frame: \(rowFrame)")

// Click the row.
click(at: CGPoint(x: rowFrame.midX, y: rowFrame.midY))

Thread.sleep(forTimeInterval: 0.8)
let final = readLog()
if final.contains("mode changed") {
    for line in final.split(separator: "\n") where line.contains("mode changed") {
        say("✓ \(line)")
    }
    exit(0)
} else {
    say("✗ mode never changed — the click didn't reach the row")
    say(String(final.suffix(800)))
    exit(3)
}
