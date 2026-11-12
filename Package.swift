// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BabyBuddyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BabyBuddyCore", targets: ["BabyBuddyCore"])],
    targets: [
        .target(name: "BabyBuddyCore"),
        .testTarget(name: "BabyBuddyCoreTests", dependencies: ["BabyBuddyCore"])
    ]
)
