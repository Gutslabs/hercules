// swift-tools-version: 5.9
// Yerel sherpa-onnx paketi. willwade/sherpa-onnx-spm'in remote sürümü iki xcframework'te de
// `module.modulemap` taşıdığı için "Multiple commands produce include/module.modulemap" hatası
// veriyordu. Burada onnxruntime'ın modulemap'i kaldırıldı (Swift'ten import edilmiyor, sadece
// link için gerekli) → tek modulemap (sherpa_onnx) kalır, çakışma biter.
// xcframework'ler vendor/sherpa/ altında (gitignore'lu); scripts/setup-sherpa.sh ile yeniden indirilir.
import PackageDescription

let package = Package(
    name: "SherpaOnnx",
    platforms: [
        .iOS(.v13),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SherpaOnnx", targets: ["SherpaOnnx"]),
    ],
    targets: [
        .binaryTarget(name: "sherpa-onnx", path: "../sherpa/sherpa_onnx.xcframework"),
        .binaryTarget(name: "onnxruntime", path: "../sherpa/onnxruntime.xcframework"),
        // C++ guard: onnxruntime TTS oturumu açarken fırlatabilir; Swift C++
        // exception yakalayamaz → çökme. Bu hedef çağrıyı try/catch içine alır.
        .target(
            name: "SherpaGuard",
            path: "Sources/SherpaGuard"
        ),
        .target(
            name: "SherpaOnnx",
            dependencies: ["sherpa-onnx", "onnxruntime", "SherpaGuard"],
            path: "Sources/SherpaOnnx",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)
