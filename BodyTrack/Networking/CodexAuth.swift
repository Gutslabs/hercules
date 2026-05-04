import Foundation

enum CodexAuthError: LocalizedError {
    case noAuthFile
    case invalidAuthFile(String)
    case refreshFailed(Int, String)
    case noRefreshToken
    case noAccountId

    var errorDescription: String? {
        switch self {
        case .noAuthFile:
            return "Codex auth dosyası bulunamadı. Önce Codex CLI'da `codex login` yap."
        case .invalidAuthFile(let s): return "Codex auth dosyası bozuk: \(s)"
        case .refreshFailed(let code, let msg): return "Token yenileme HTTP \(code): \(msg)"
        case .noRefreshToken: return "Refresh token yok. `codex login` ile yeniden giriş yap."
        case .noAccountId: return "Token içinde ChatGPT account ID yok."
        }
    }
}

struct CodexTokens: Codable {
    var access_token: String
    var refresh_token: String?
    var id_token: String?
    var account_id: String?

    /// JWT'den ChatGPT account ID'sini çıkar (Cloudflare header için gerekli).
    var chatGPTAccountId: String? {
        if let acct = account_id, !acct.isEmpty { return acct }
        return Self.extractAccountId(from: access_token)
    }

    /// JWT exp claim'inden expire zamanı.
    var expiry: Date? {
        Self.extractExpiry(from: access_token)
    }

    var isExpiringSoon: Bool {
        guard let exp = expiry else { return false }
        return exp.timeIntervalSinceNow < 60  // 1 dk içinde dolacaksa yenile
    }

    static func extractClaims(from jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        // base64url padding
        while payload.count % 4 != 0 { payload += "=" }
        // base64url -> base64
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    static func extractAccountId(from jwt: String) -> String? {
        guard let claims = extractClaims(from: jwt) else { return nil }
        if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
           let acct = auth["chatgpt_account_id"] as? String,
           !acct.isEmpty {
            return acct
        }
        return nil
    }

    static func extractExpiry(from jwt: String) -> Date? {
        guard let claims = extractClaims(from: jwt),
              let exp = claims["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

private struct AuthFileRoot: Codable {
    var auth_mode: String?
    var tokens: CodexTokens?
    var last_refresh: String?
    var OPENAI_API_KEY: String?
}

private struct RefreshResponse: Codable {
    var access_token: String?
    var refresh_token: String?
    var id_token: String?
    var expires_in: Int?
    var error: String?
    var error_description: String?
}

/// ~/.codex/auth.json okur, gerekirse yeniler ve kendi store'umuzda tutar.
@MainActor
final class CodexAuth {
    static let shared = CodexAuth()

    private let oauthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let oauthTokenURL = URL(string: "https://auth.openai.com/oauth/token")!

    /// Hercules'in kendi Codex token kopyası — Codex CLI ile refresh çakışması olmasın diye.
    private var herculesStoreURL: URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.homeDirectoryForCurrentUser
        let dir = support.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("codex_auth.json")
    }

    private var codexCLIAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    /// Codex CLI'ın auth.json'ından geçerli bir token var mı?
    var codexCLIInstalled: Bool {
        FileManager.default.fileExists(atPath: codexCLIAuthURL.path)
    }

    /// Hercules'in kendi store'unda token var mı?
    var hasHerculesTokens: Bool {
        FileManager.default.fileExists(atPath: herculesStoreURL.path)
    }

    /// Geçerli erişim token'ı al — gerektiğinde otomatik yenile.
    /// İlk defa çağrılırsa Codex CLI'dan import et.
    func ensureFreshToken() async throws -> CodexTokens {
        var tokens = try loadTokens()
        if tokens.isExpiringSoon {
            tokens = try await refresh(tokens)
        }
        return tokens
    }

    /// Codex CLI'dan ilk seferlik import (Hercules store'una kopyala).
    @discardableResult
    func importFromCodexCLI() throws -> CodexTokens {
        guard FileManager.default.fileExists(atPath: codexCLIAuthURL.path) else {
            throw CodexAuthError.noAuthFile
        }
        let data = try Data(contentsOf: codexCLIAuthURL)
        let root = try JSONDecoder().decode(AuthFileRoot.self, from: data)
        guard let t = root.tokens, !t.access_token.isEmpty else {
            throw CodexAuthError.invalidAuthFile("tokens.access_token yok")
        }
        try saveTokens(t)
        return t
    }

    /// Hercules store'undan token oku, yoksa Codex CLI'dan import et.
    func loadTokens() throws -> CodexTokens {
        if FileManager.default.fileExists(atPath: herculesStoreURL.path) {
            let data = try Data(contentsOf: herculesStoreURL)
            return try JSONDecoder().decode(CodexTokens.self, from: data)
        }
        // İlk kullanım — Codex CLI'dan import dene
        return try importFromCodexCLI()
    }

    func saveTokens(_ tokens: CodexTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try data.write(to: herculesStoreURL, options: [.atomic])
    }

    /// Token'ı refresh endpoint'ine post ederek yenile.
    func refresh(_ tokens: CodexTokens) async throws -> CodexTokens {
        guard let refreshToken = tokens.refresh_token, !refreshToken.isEmpty else {
            throw CodexAuthError.noRefreshToken
        }

        var req = URLRequest(url: oauthTokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauthClientID,
            "scope": "openid profile email offline_access"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let status = http?.statusCode ?? -1

        let decoded = (try? JSONDecoder().decode(RefreshResponse.self, from: data)) ?? RefreshResponse()
        if status < 200 || status >= 300 || decoded.access_token == nil {
            let msg = decoded.error_description ?? decoded.error ?? String(data: data, encoding: .utf8) ?? "?"
            throw CodexAuthError.refreshFailed(status, msg)
        }

        var updated = tokens
        updated.access_token = decoded.access_token!
        if let nrt = decoded.refresh_token, !nrt.isEmpty {
            updated.refresh_token = nrt  // OpenAI rotates refresh tokens
        }
        if let nid = decoded.id_token, !nid.isEmpty {
            updated.id_token = nid
        }
        try saveTokens(updated)
        return updated
    }

    /// Codex bağlantı durumu — UI için.
    enum Status {
        case noCodexCLI                    // ~/.codex/auth.json yok
        case ready(account: String?)       // Hazır, çağrı yapılabilir
        case error(String)
    }

    func currentStatus() -> Status {
        if !codexCLIInstalled && !hasHerculesTokens {
            return .noCodexCLI
        }
        do {
            let t = try loadTokens()
            return .ready(account: t.chatGPTAccountId)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
