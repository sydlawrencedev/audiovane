// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VisualiserMac",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(name: "VisualiserMac", targets: ["VisualiserMac"])
    ],
    targets: [
        .executableTarget(
            name: "VisualiserMac",
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
        )
    ]
)