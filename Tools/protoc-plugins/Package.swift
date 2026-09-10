// swift-tools-version: 6.0
// Builds the protoc plugins used by Scripts/gen-proto.sh. Not part of the app.
import PackageDescription

let package = Package(
    name: "protoc-plugins",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.29.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.0.0"),
    ],
    targets: [
        // Empty target so the package resolves; the plugins are products of the
        // dependencies and are built with `swift build --product`.
        .target(name: "PluginAnchor", path: "Sources/PluginAnchor"),
    ]
)
