// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IGoogle",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "IGoogle", targets: ["IGoogleApp"]),
        .library(name: "IGoogleCore", targets: ["IGoogleCore"]),
    ],
    targets: [
        // Сетевой/логический слой без UI. Содержит WebSocket-сервер,
        // Bonjour-объявление, монитор буфера обмена и протокол сообщений.
        .target(
            name: "IGoogleCore",
            path: "Sources/IGoogleCore"
        ),
        // SwiftUI-приложение (хаб на Mac).
        .executableTarget(
            name: "IGoogleApp",
            dependencies: ["IGoogleCore"],
            path: "Sources/IGoogleApp"
        ),
        .testTarget(
            name: "IGoogleCoreTests",
            dependencies: ["IGoogleCore"],
            path: "Tests/IGoogleCoreTests"
        ),
    ]
)
