// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Caffelid",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Caffelid", targets: ["Caffelid"]),
        .executable(name: "CaffelidHelper", targets: ["CaffelidHelper"])
    ],
    targets: [
        .target(name: "CaffelidIPC", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("Security"), .linkedFramework("CoreFoundation")]),
        .target(name: "CaffelidSensors", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "Caffelid", dependencies: ["CaffelidIPC", "CaffelidSensors"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement"),
                                           .linkedFramework("IOKit")]),
        .executableTarget(name: "CaffelidHelper", dependencies: ["CaffelidIPC"]),
        .testTarget(name: "CaffelidTests", dependencies: ["Caffelid"], path: "Tests/Swift")
    ]
)
