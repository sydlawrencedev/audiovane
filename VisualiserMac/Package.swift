// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AudioVane",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(name: "AudioVane", targets: ["AudioVane"]),
        .executable(name: "AudioVaneWatcher", targets: ["AudioVaneWatcher"])
    ],
    targets: [
        .executableTarget(
            name: "AudioVane",
            path: "Sources/VisualiserMac",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
                .define("GL_SILENCE_DEPRECATION")
            ],
            linkerSettings: [
                .linkedFramework("OpenGL"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreVideo")
            ]
        ),
        // Launched by launchd, not by the user: sits in the bundle as
        // Contents/Helpers and opens AudioVane when Apple Music or Spotify
        // starts. Plain AppKit so it stays tiny.
        .executableTarget(
            name: "AudioVaneWatcher",
            path: "Sources/AudioVaneWatcher",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ]
)