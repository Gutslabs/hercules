import Foundation

final class OllamaClient: AIClient {

    private static var systemPrompt: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMMM yyyy"
        let today = fmt.string(from: .now)
        return """
        Bugün: \(today). Türkçe konuşan bir fitness ve beslenme koçusun.
        SADECE geçerli, tek satır JSON döndür; JSON dışında hiçbir şey yazma. <...> ile yazılan yerleri gerçek içerikle doldur; ŞABLONDAKİ metinleri ("<...>") asla aynen yazma. 0'ları da gerçek değerle değiştir.

        Moda göre yanıt ver:
        1) Yemek kaydı (kullanıcı "ekle/kaydet/yedim/içtim" derse):
        {"message":"<kısa onay, ör. '200 gr tavuk göğsü eklendi'>","actions":[{"tool":"log_food","summary":"<özet>","name":"<yemek adı>","grams":0,"calories":0,"protein_g":0,"carbs_g":0,"fat_g":0,"vitamin_c_mg":0,"vitamin_b1_mg":0,"vitamin_b6_mg":0,"potassium_mg":0,"magnesium_mg":0,"vitamin_a_ug":0,"vitamin_d_ug":0,"vitamin_e_mg":0,"vitamin_k_ug":0,"vitamin_b12_ug":0,"folate_ug":0,"iron_mg":0,"zinc_mg":0,"calcium_mg":0,"omega3_g":0}]}
        2) Yemek bilgisi (ekle demeden sorarsa) — message'ı en başa yaz:
        {"message":"<kısa açıklama>","name":"<yemek adı>","grams":0,"calories":0,"protein_g":0,"carbs_g":0,"fat_g":0}
        3) Sohbet (diğer her şey):
        {"message":"<kullanıcıya kısa, gerçek Türkçe yanıtın>"}

        ÇOKLU YEMEK (en kritik kural): Mesajda birden fazla yiyecek varsa MUTLAKA mod 1 kullan ve actions dizisine HER yiyecek için AYRI bir log_food ekle. Yiyecekleri tek bir kayda BİRLEŞTİRME. "name" daima tek bir yiyeceğin adıdır (ör. "Haşlanmış Yumurta", "Muz") — ASLA "Kahvaltı"/"Öğün"/"Akşam yemeği" gibi öğün adı yazma. "yedim/içtim/ekle/kaydet" geçen mesaj kayıttır → mod 2 (tek bilgi kartı) DEĞİL, mod 1 (actions) kullan.

        Kurallar: grams/calories ve protein_g/carbs_g/fat_g HER yiyecekte gerçekçi porsiyon tahminiyle doldur; ASLA 0 bırakma (ör. 2 haşlanmış yumurta ≈ 100g/140 kcal/P12/F10; 1 muz ≈ 120g/105 kcal). Bilinen vitamin/mineral alanlarını da gerçek değerlerle doldur, sadece gerçekten bilmediğin nadir mikroyu 0 bırak; null kullanma. Örnek 200g tavuk göğsü: calories 330, protein_g 62, fat_g 7, potassium_mg 340, magnesium_mg 29, vitamin_b6_mg 0.9, zinc_mg 2.
        """
    }
    // Ollama'nın native /api/chat ucu — OpenAI uyumlu /v1 ucundan farklı olarak
    // `options.num_ctx` ile bağlam penceresini ayarlamaya izin verir.
    private let endpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    private let model = "qwen2.5:14b"

    /// Bağlam penceresi (token). Ollama varsayılanı 4096; veri yoğun koçluk
    /// promptları (sistem + 10 tur geçmiş + skill/kişisel-model bağlamı) bunu
    /// aşıp en eski tokenların (JSON format talimatı dahil) sessizce kırpılmasına
    /// yol açıyordu. 8192 tipik promptların tamamının modele ulaşmasını sağlar.
    private static let contextWindow = 8192

    /// Açılışta (veya Ollama'ya geçildiğinde) modeli belleğe yükler ki ilk mesaj soğuk başlamasın.
    /// Warm-up ile gerçek istekler aynı num_ctx'i kullanmalı; aksi halde ilk istek modeli yeniden yükler.
    static func warmUp() {
        Task.detached(priority: .utility) {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": "qwen2.5:14b",
                "stream": false,
                "keep_alive": "30m",
                "options": ["num_ctx": contextWindow],
                "messages": [["role": "user", "content": "hi"]]
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func send(
        history: [ChatTurn],
        newUserText: String,
        userContext: String?,
        onSearchStart: @MainActor @escaping (String) -> Void,
        onMessageUpdate: @MainActor @escaping (String) -> Void
    ) async throws -> (AIFoodResult, String?) {

        // Mesajları oluştur
        var messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPrompt]
        ]
        for turn in history.suffix(10) {
            messages.append(["role": turn.role.rawValue, "content": turn.text])
        }
        let userContent: String = {
            guard let ctx = userContext, !ctx.isEmpty else { return newUserText }
            return "\(ctx)\n\n---\n\(newUserText)"
        }()
        messages.append(["role": "user", "content": userContent])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "format": "json",
            "options": [
                "temperature": 0.1,
                "num_ctx": Self.contextWindow
            ],
            // Modeli isteklerden sonra 30 dk GPU'da tut; aksi halde varsayılan 5 dk
            // sonra atılır ve sonraki istek soğuk başlayıp çok yavaşlar.
            "keep_alive": "30m"
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 120

        let session = URLSession.shared
        let (stream, response) = try await session.bytes(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OllamaError.httpError(http.statusCode)
        }

        var accumulated = ""
        // Native /api/chat akışı: her satır bağımsız bir JSON nesnesi
        // ({"message":{"content":"…"},"done":false}); SSE "data:" öneki yok.
        for try await line in stream.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty,
                  let data = trimmedLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let message = json["message"] as? [String: Any],
               let token = message["content"] as? String, !token.isEmpty {
                accumulated += token
                // JSON akarken "message" alanının o ana kadarki (kısmi) değerini canlı göster:
                // kullanıcı ham JSON'u değil, mesajı token token görür.
                if let partial = Self.partialMessage(from: accumulated) {
                    await onMessageUpdate(partial)
                } else {
                    // JSON olmayan düz metin cevabı (güvenlik için): olduğu gibi akıt.
                    let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.hasPrefix("{") && !trimmed.hasPrefix("```") {
                        await onMessageUpdate(accumulated)
                    }
                }
            }

            if (json["done"] as? Bool) == true { break }
        }

        guard !accumulated.isEmpty else {
            throw OllamaError.emptyResponse
        }

        // JSON parse et — AIFoodResult'a çevir
        let cleaned = stripCodeFences(accumulated)
        if let data = cleaned.data(using: .utf8),
           let result = try? JSONDecoder().decode(AIFoodResult.self, from: data) {
            return (result, nil)
        }
        return (AIFoodResult(message: accumulated), nil)
    }

    /// Akan ham JSON içinden "message" alanının o ana kadarki değerini çıkarır.
    /// Henüz kapanmamışsa kısmi metni, kapanmışsa tam metni döndürür. Bulamazsa nil.
    static func partialMessage(from raw: String) -> String? {
        guard let keyRange = raw.range(of: "\"message\"") else { return nil }
        var idx = keyRange.upperBound

        // ':' bul
        while idx < raw.endIndex, raw[idx] != ":" { idx = raw.index(after: idx) }
        guard idx < raw.endIndex else { return nil }
        idx = raw.index(after: idx)

        // Değerin açılış tırnağını bul (arada sadece boşluk olmalı)
        while idx < raw.endIndex, raw[idx] != "\"" {
            if !raw[idx].isWhitespace { return nil } // string değilse (null/sayı) vazgeç
            idx = raw.index(after: idx)
        }
        guard idx < raw.endIndex else { return nil }
        idx = raw.index(after: idx) // açılış tırnağını geç

        // Kapanış tırnağına kadar oku, JSON kaçışlarını çöz
        var out = ""
        var escaping = false
        while idx < raw.endIndex {
            let ch = raw[idx]
            if escaping {
                switch ch {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": break
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                default: out.append(ch)
                }
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else if ch == "\"" {
                return out // kapanış tırnağı: mesaj tamam
            } else {
                out.append(ch)
            }
            idx = raw.index(after: idx)
        }
        return out // henüz kapanmadı: kısmi metin
    }

    private func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum OllamaError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Ollama'dan geçersiz yanıt."
        case .httpError(let code): return "Ollama HTTP hatası: \(code). Ollama çalışıyor mu?"
        case .emptyResponse: return "Ollama boş yanıt döndü."
        }
    }
}
