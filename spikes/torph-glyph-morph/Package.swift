// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TorphGlyphMorph",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TorphGlyphMorph", path: "Sources/TorphGlyphMorph")
    ]
)
