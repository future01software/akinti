// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Akinti", platforms: [.macOS(.v14)], products: [.executable(name: "Akinti", targets: ["Akinti"])], targets: [.executableTarget(name: "Akinti"), .testTarget(name: "AkintiTests", dependencies: ["Akinti"], exclude: ["server.py", "fake-yt-dlp", "torrent_fixture.py"])])
