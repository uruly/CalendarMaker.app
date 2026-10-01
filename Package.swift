// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarMaker",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "CalendarMaker", targets: ["CalendarMaker"])],
    targets: [
        .executableTarget(
            name: "CalendarMaker",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CalendarMakerTests", dependencies: ["CalendarMaker"])
    ]
)
