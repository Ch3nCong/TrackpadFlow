// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrackpadFlow",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TrackpadFlow", targets: ["TrackpadFlow"])],
    targets: [
        .target(name: "TrackpadBridge", linkerSettings: [.linkedFramework("CoreFoundation")]),
        .executableTarget(name: "TrackpadFlow", dependencies: ["TrackpadBridge"]),
        .testTarget(name: "TrackpadFlowTests", dependencies: ["TrackpadFlow"])
    ]
)
