// swift-tools-version: 6.0
// Phase 0 throwaway spike. Drives a running emulator (-grpc 8554) to answer
// docs/SPIKE-NOTES.md. Deleted after Phase 1.
import PackageDescription

let package = Package(
    name: "Spike",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.9.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.4.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.29.0"),
    ],
    targets: [
        .executableTarget(
            name: "Spike",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/Spike",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
