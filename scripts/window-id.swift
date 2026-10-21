#!/usr/bin/env swift
// Prints the window id of an app's frontmost window, for `screencapture -l`.
//
//   swift scripts/window-id.swift Vibresia
//
// Screen recording permission is needed for the id to be useful, and for
// `screencapture -l` to capture anything at all.

import CoreGraphics
import Foundation

let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Vibresia"

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("could not list windows")
    exit(1)
}

for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.localizedCaseInsensitiveContains(wanted) else { continue }
    let name = window[kCGWindowName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    guard layer == 0 else { continue }   // 0 is the normal window layer
    let id = window[kCGWindowNumber as String] as? Int ?? 0
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = bounds["Width"] as? Int ?? 0
    let height = bounds["Height"] as? Int ?? 0
    print("\(id)\t\(owner)\t\(name)\t\(width)x\(height)")
}
