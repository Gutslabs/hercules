import Foundation
import CoreML
import Embeddings
import Hub

@MainActor
final class EmbeddingStatus {
    static let shared = EmbeddingStatus()

    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double)   // model indiriliyor (0...1)
        case backfilling(done: Int, total: Int)
        case ready                           // semantic arama aktif
        case unavailable                     // yüklenemedi → lexical
    }

    private(set) var phase: Phase = .idle

    func set(_ newPhase: Phase) {
        // Geç gelen download progress callback'i, indirme bittikten sonra UI'ı geri sarmasın.
        if case .downloading = newPhase {
            switch phase {
            case .backfilling, .ready: return
            default: break
            }
        }
        guard newPhase != phase else { return }
        phase = newPhase
        NotificationCenter.default.post(name: .embeddingStatusChanged, object: nil)
    }
}

/// Mem0 tarzı LLM "memory manager": her konuşma turundan sonra arka planda çalışır,
/// kalıcı/kullanıcıya özel fact'leri çıkarır ve mevcut hafızayla karşılaştırıp
/// ADD/UPDATE/DELETE/NOOP kararı verir. LLM ulaşılamaz/hatalıysa veya yanıt
/// çözümlenemezse, eski keyword-heuristik (`absorbConversation`) fallback devreye girer.

actor EmbeddingService {
    static let shared = EmbeddingService()

    static let modelID = "jkrukowski/Qwen3-Embedding-0.6B-F32"
    static let dimension = 1024

    /// swift-embeddings'in indirdiği dosya kümesiyle aynı (loadModelBundle bunları bekler).
    static let modelGlobs = ["*.json", "*.safetensors", "*.py", "tokenizer.model", "sentencepiece*.model", "*.tiktoken", "*.txt"]

    /// HubApi'nin default indirme konumu: ~/Documents/huggingface/models/<repo-id>.
    /// Kullanıcı dosyaları buraya terminalden indirirse, app indirmeyi atlayıp doğrudan yükler.
    static func localModelFolder() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents")
        return docs.appending(path: "huggingface").appending(path: "models").appending(path: modelID)
    }

    private static func folderHasModel(_ folder: URL) -> Bool {
        let fm = FileManager.default
        return ["model.safetensors", "config.json", "tokenizer.json"].allSatisfy {
            fm.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    private var bundle: Qwen3.ModelBundle?
    private var loadFailed = false
    private var loadTask: Task<Qwen3.ModelBundle?, Never>?

    var isLoaded: Bool { bundle != nil }

    /// Modeli indir/yükle (gerekiyorsa). Idempotent; başarısızsa bu oturumda tekrar denemez.
    @discardableResult
    func warmUp() async -> Bool {
        await ensureModel() != nil
    }

    /// Model DİSKTE hazırsa RAM'e yükle; yoksa hiçbir şey yapma (indirme TETİKLEMEZ).
    /// App launch'ta arka planda çağrılır — semantic retrieval, Hafıza ekranı açılmasa
    /// bile her sohbette hazır olsun. Model henüz inmemişse sessizce atlar.
    func warmUpIfDownloaded() async {
        guard bundle == nil, !loadFailed else { return }
        guard Self.folderHasModel(Self.localModelFolder()) else { return }
        _ = await ensureModel()
    }

    /// Model HAZIRSA query'yi (Qwen3 instruct prefix ile) embed et; değilse nil.
    func embedQueryIfAvailable(_ query: String) async -> [Float]? {
        guard bundle != nil else { return nil }
        return await embed(Self.queryPrompt(query))
    }

    /// Model HAZIRSA dökümanı (ham) embed et; değilse nil.
    func embedDocumentIfAvailable(_ text: String) async -> [Float]? {
        guard bundle != nil else { return nil }
        return await embed(text)
    }

    private static func queryPrompt(_ query: String) -> String {
        "Instruct: Bir kullanıcı mesajına en alakalı kişisel hafıza kayıtlarını getir\nQuery: \(query)"
    }

    private func ensureModel() async -> Qwen3.ModelBundle? {
        if let bundle { return bundle }
        if loadFailed { return nil }
        if let loadTask { return await loadTask.value }
        let task = Task<Qwen3.ModelBundle?, Never> {
            // 1) Model dosyaları diskte hazırsa (ör. terminalden indirildiyse) doğrudan yükle — indirme YOK.
            let localFolder = Self.localModelFolder()
            if Self.folderHasModel(localFolder), let local = try? await Qwen3.loadModelBundle(from: localFolder) {
                return local
            }
            // 2) Değilse Hub'dan indir (gerçek % progress ile) ve yükle.
            do {
                let repo = Hub.Repo(id: Self.modelID, type: .models)
                let folder = try await HubApi().snapshot(from: repo, matching: Self.modelGlobs) { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        EmbeddingStatus.shared.set(.downloading(fraction: fraction))
                    }
                }
                return try await Qwen3.loadModelBundle(from: folder)
            } catch {
                return nil
            }
        }
        loadTask = task
        let result = await task.value
        loadTask = nil
        if let result { bundle = result } else { loadFailed = true }
        return result
    }

    private func embed(_ text: String) async -> [Float]? {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        guard !clean.isEmpty, let bundle else { return nil }
        do {
            let tensor = try bundle.encode(clean)
            let scalars = await tensor.cast(to: Float.self).shapedArray(of: Float.self).scalars
            return scalars.isEmpty ? nil : scalars
        } catch {
            return nil
        }
    }
}

enum EmbeddingMath {
    /// Kosinüs benzerliği. Qwen3 çıktısı L2-normalize olduğundan pratikte dot product.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}
