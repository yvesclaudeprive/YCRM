// swift-tools-version:5.10
import PackageDescription

// Logique Pipedrive sans interface : compile sur iOS, macOS et Linux (tests en CI).
let package = Package(
    name: "PipedriveKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PipedriveKit", targets: ["PipedriveKit"]),
    ],
    targets: [
        .target(name: "PipedriveKit"),
        .testTarget(name: "PipedriveKitTests", dependencies: ["PipedriveKit"]),
    ]
)
