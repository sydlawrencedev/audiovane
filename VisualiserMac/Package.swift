// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AudioVane",
    platforms: [
        .macOS("14.2")
    ],
    // The products are named for the app; the targets keep their old names
    // so the Swift module — and everything in it — doesn't have to change.
    products: [
        .executable(name: "Vibresia", targets: ["AudioVane"]),
        .executable(name: "VibresiaWatcher", targets: ["AudioVaneWatcher"])
    ],
    dependencies: [
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.58.0")
    ],
    targets: [
        // The logo, in one place. The app draws it in its header and on the
        // share picture it uploads; the share-graphics tool draws it on the
        // website's built-in share pictures. One implementation, so the app and
        // its own share images can't drift apart.
        .target(
            name: "VibresiaBrand",
            path: "Sources/VibresiaBrand"
        ),
        .executableTarget(
            name: "AudioVane",
            dependencies: [
                .product(name: "PostHog", package: "posthog-ios"),
                "VibresiaBrand",
            ],
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
        // Draws the website's share pictures for every built-in vibescape.
        // Not part of the app: it is a build-time tool, run by hand when a
        // vibescape changes. See scripts/build-share-graphics.sh.
        .executableTarget(
            name: "ShareGraphics",
            dependencies: [
                "VibresiaBrand"
            ],
            path: "Sources/ShareGraphics"
        ),
        // Launched by launchd, not by the user: sits in the bundle as
        // Contents/Helpers and opens Vibresia when Apple Music or Spotify
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