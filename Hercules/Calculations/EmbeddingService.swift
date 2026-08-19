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

    /// Qwen3-0.6B-F32 uygulama boşta dururken yaklaşık 2.4 GB CoreML belleği tutuyordu.
    /// multilingual-e5-small Türkçe dahil 100 dili destekler ve yaklaşık beşte bir boyuttadır.
    static let modelID = "intfloat/multilingual-e5-small"
    private static let modelDimension = 384

    /// Eski Qwen embedding arşivleri 1024 boyutluydu. Persist/backup şemasını kırmamak için
    /// E5'in 384 boyutlu normalize çıktısını sıfırlarla 1024'e tamamlıyoruz. Cosine skoru
    /// değişmez; modelID değiştiği için eski vektörler de normal backfill ile yenilenir.
    static let dimension = 1024
    private static let maxTokenCount = 256
    private static let idleUnloadDelay: Duration = .seconds(90)

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
        let hasCoreFiles = ["model.safetensors", "config.json", "tokenizer.json"].allSatisfy {
            fm.fileExists(atPath: folder.appending(path: $0).path)
        }
        guard hasCoreFiles,
              let contents = try? fm.contentsOfDirectory(
                  at: folder,
                  includingPropertiesForKeys: nil
              )
        else { return false }
        return contents.contains {
            $0.pathExtension == "model" && $0.lastPathComponent.contains("sentencepiece")
        }
    }

    private var bundle: XLMRoberta.ModelBundle?
    private var loadFailed = false
    private var loadTask: Task<XLMRoberta.ModelBundle?, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private var idleGeneration: UInt64 = 0
    private var activeOperations = 0
    private var unloadWhenIdle = false

    var isLoaded: Bool { bundle != nil }

    /// Modeli indir/yükle (gerekiyorsa). Idempotent; başarısızsa bu oturumda tekrar denemez.
    @discardableResult
    func warmUp() async -> Bool {
        beginOperation()
        defer { endOperation() }
        return await ensureModel(allowDownload: true) != nil
    }

    /// Model DİSKTE hazırsa RAM'e yükle; yoksa hiçbir şey yapma (indirme TETİKLEMEZ).
    /// Yalnız gerçek bir semantic sorgu veya açık kullanıcı eylemi çağırır.
    func warmUpIfDownloaded() async {
        guard bundle == nil, !loadFailed else { return }
        guard Self.folderHasModel(Self.localModelFolder()) else { return }
        beginOperation()
        defer { endOperation() }
        _ = await ensureModel(allowDownload: false)
    }

    /// Model diskteyse ihtiyaç anında RAM'e alıp query'yi embed et. Diskte yoksa indirme
    /// başlatmadan nil döner; çağıran lexical aramaya düşer.
    func embedQueryIfAvailable(_ query: String) async -> [Float]? {
        guard bundle != nil || Self.folderHasModel(Self.localModelFolder()) else { return nil }
        beginOperation()
        defer { endOperation() }
        guard await ensureModel(allowDownload: false) != nil else { return nil }
        return await embed(query, prefix: "query: ")
    }

    /// Model HAZIRSA dökümanı (ham) embed et; değilse nil.
    func embedDocumentIfAvailable(_ text: String) async -> [Float]? {
        guard bundle != nil else { return nil }
        beginOperation()
        defer { endOperation() }
        return await embed(text, prefix: "passage: ")
    }

    /// Uygulama odağı kaybolduğunda veya idle süresi dolduğunda model ağırlıklarını bırak.
    /// Devam eden inference/download varsa release o operasyon tamamlanınca yapılır.
    func unload() {
        idleGeneration &+= 1
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        guard activeOperations == 0 else {
            unloadWhenIdle = true
            return
        }
        releaseModel()
    }

    private func ensureModel(allowDownload: Bool) async -> XLMRoberta.ModelBundle? {
        if let bundle { return bundle }
        if loadFailed { return nil }
        if let loadTask { return await loadTask.value }
        if !allowDownload && !Self.folderHasModel(Self.localModelFolder()) { return nil }

        let task = Task<XLMRoberta.ModelBundle?, Never> {
            // 1) Model dosyaları diskte hazırsa (ör. terminalden indirildiyse) doğrudan yükle — indirme YOK.
            let localFolder = Self.localModelFolder()
            if Self.folderHasModel(localFolder),
               let local = try? await XLMRoberta.loadModelBundle(from: localFolder) {
                return local
            }
            guard allowDownload else { return nil }
            // 2) Değilse Hub'dan indir (gerçek % progress ile) ve yükle.
            do {
                let repo = Hub.Repo(id: Self.modelID, type: .models)
                let folder = try await HubApi().snapshot(from: repo, matching: Self.modelGlobs) { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        EmbeddingStatus.shared.set(.downloading(fraction: fraction))
                    }
                }
                return try await XLMRoberta.loadModelBundle(from: folder)
            } catch {
                return nil
            }
        }
        loadTask = task
        let result = await task.value
        loadTask = nil
        if let result {
            bundle = result
            loadFailed = false
        } else if allowDownload {
            loadFailed = true
        }
        return result
    }

    /// E5: token çıktılarının attention-mask mean pooling'i + L2 normalization.
    /// Tek metin/padding olmadığı için bütün token'ların mask değeri 1'dir.
    private func embed(_ text: String, prefix: String) async -> [Float]? {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        guard !clean.isEmpty, let bundle else { return nil }
        do {
            let tokens = try bundle.tokenizer.tokenizeText(
                prefix + clean,
                maxLength: Self.maxTokenCount
            )
            guard !tokens.isEmpty else { return nil }
            let inputIDs = MLTensor(shape: [1, tokens.count], scalars: tokens)
            let sequence = bundle.model(inputIds: inputIDs).sequenceOutput
            let scalars = await sequence.cast(to: Float.self).shapedArray(of: Float.self).scalars
            return Self.meanPoolNormalizeAndPad(scalars, tokenCount: tokens.count)
        } catch {
            return nil
        }
    }

    private nonisolated static func meanPoolNormalizeAndPad(
        _ scalars: [Float],
        tokenCount: Int
    ) -> [Float]? {
        guard tokenCount > 0, scalars.count == tokenCount * modelDimension else { return nil }
        var pooled = [Float](repeating: 0, count: modelDimension)
        for token in 0..<tokenCount {
            let offset = token * modelDimension
            for index in 0..<modelDimension {
                pooled[index] += scalars[offset + index]
            }
        }
        let divisor = Float(tokenCount)
        var normSquared: Float = 0
        for index in pooled.indices {
            pooled[index] /= divisor
            normSquared += pooled[index] * pooled[index]
        }
        guard normSquared.isFinite, normSquared > 0 else { return nil }
        let norm = normSquared.squareRoot()
        for index in pooled.indices { pooled[index] /= norm }
        pooled.append(
            contentsOf: repeatElement(
                0,
                count: max(0, dimension - modelDimension)
            )
        )
        return pooled
    }

    private func beginOperation() {
        activeOperations += 1
        unloadWhenIdle = false
        idleGeneration &+= 1
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    private func endOperation() {
        activeOperations = max(0, activeOperations - 1)
        guard activeOperations == 0 else { return }
        if unloadWhenIdle {
            releaseModel()
        } else {
            scheduleIdleUnload()
        }
    }

    private func scheduleIdleUnload() {
        guard bundle != nil else { return }
        idleGeneration &+= 1
        let generation = idleGeneration
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.idleUnloadDelay)
            } catch {
                return
            }
            await self?.unloadIfIdle(generation: generation)
        }
    }

    private func unloadIfIdle(generation: UInt64) {
        guard generation == idleGeneration, activeOperations == 0 else { return }
        releaseModel()
    }

    private func releaseModel() {
        bundle = nil
        unloadWhenIdle = false
        idleUnloadTask = nil
    }
}

enum EmbeddingMath {
    /// Kosinüs benzerliği. E5 çıktısı L2-normalize olduğundan pratikte dot product.
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
