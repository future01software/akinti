// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Akinti",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Akinti", targets: ["Akinti"]),
        .executable(name: "akinti-bridge", targets: ["AkintiBridge"]),
    ],
    targets: [
        // Uygulama ile tarayıcı köprüsünün paylaştığı küçük kod (akinti:// bağlantıları, köprü mesajları).
        .target(name: "AkintiShared"),
        .executableTarget(name: "Akinti", dependencies: ["AkintiShared"]),
        // Chrome/Brave/Edge/Arc eklentisinin Native Messaging köprüsü (Contents/Helpers/akinti-bridge).
        .executableTarget(name: "AkintiBridge", dependencies: ["AkintiShared"]),
        .testTarget(name: "AkintiTests", dependencies: ["Akinti", "AkintiShared", "AkintiBridge"],
                    exclude: ["server.py", "fake-yt-dlp", "torrent_fixture.py"]),
    ]
)
