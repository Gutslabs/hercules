// swift-tools-version: 6.0
import PackageDescription

// iOS de beyan EDİLMELİ. Paket yalnız macOS hedefine bağlansa bile Xcode paket
// grafiğini proje genelinde çözüyor; projede bir iOS hedefi (HerculesMobile) olduğu
// için yalnız-macOS bir yerel paket, proje düzeyinde "Missing package product"
// hatası veriyordu. (Kardeş yerel paket LucideKit de ikisini birden beyan ediyor.) İçerik saf Foundation DTO'ları — platforma özel hiçbir şey yok.
let package = Package(
    name: "HerculesIslandBridge",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(
            name: "HerculesIslandBridge",
            targets: ["HerculesIslandBridge"]
        )
    ],
    targets: [
        .target(name: "HerculesIslandBridge"),
        .testTarget(
            name: "HerculesIslandBridgeTests",
            dependencies: ["HerculesIslandBridge"]
        )
    ]
)
