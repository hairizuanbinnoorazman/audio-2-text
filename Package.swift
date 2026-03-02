// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioToText",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AudioToText",
            dependencies: [
                .product(name: "AWSTranscribeStreaming", package: "aws-sdk-swift"),
            ],
            exclude: ["Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ]
)
