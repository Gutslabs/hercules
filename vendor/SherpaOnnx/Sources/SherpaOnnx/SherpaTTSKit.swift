import Foundation

/// Yüksek seviye, **public** TTS sarmalayıcısı. Paket içindeki (internal) SherpaOnnx.swift
/// wrapper'ını kullanır ve uygulamaya tek bir public yüzey sunar — böylece wrapper'ın onlarca
/// sembolünü public yapmaya / default-argüman zincirini app modülüne taşımaya gerek kalmaz.
public final class SherpaTTSEngine {
    private let tts: SherpaOnnxOfflineTtsWrapper

    /// VITS/Piper modeli yükler. Model açılamazsa `nil` döner (app Apple sesine düşer).
    public init?(model: String, tokens: String, dataDir: String) {
        let vits = sherpaOnnxOfflineTtsVitsModelConfig(
            model: model, lexicon: "", tokens: tokens, dataDir: dataDir)
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            vits: vits, numThreads: 2, debug: 0, provider: "cpu")
        var config = sherpaOnnxOfflineTtsConfig(model: modelConfig)
        let wrapper = SherpaOnnxOfflineTtsWrapper(config: &config)
        guard wrapper.tts != nil else { return nil }   // SherpaOnnxCreateOfflineTts başarısız oldu
        self.tts = wrapper
    }

    /// Metni seslendirip WAV dosyasına yazar. Başarılıysa `true`.
    @discardableResult
    public func synthesizeWav(text: String, toPath path: String, speed: Float = 1.0) -> Bool {
        let audio = tts.generate(text: text, sid: 0, speed: speed)
        guard audio.n > 0 else { return false }
        return audio.save(filename: path) == 1
    }
}
