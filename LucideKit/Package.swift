// swift-tools-version: 5.9
import PackageDescription

// LucideKit — Lucide (https://lucide.dev) ikonları SwiftUI'de.
// Bundle'lanmış `lucide.ttf` fontundan glyph render eder. App target'ları
// buna bağlanır (tek kaynak; kopya yok). Lucide ISC lisanslı.
let package = Package(
    name: "LucideKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LucideKit", targets: ["LucideKit"])
    ],
    targets: [
        .target(
            name: "LucideKit",
            resources: [.process("lucide.ttf")]
        )
    ]
)
