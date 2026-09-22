import Foundation
import CryptoKit
import Security
#if canImport(Darwin)
import Darwin
#endif

/// Hercules hafızası için ayrı AES-GCM domain'i.
/// Keychain erişim hatası asla "ilk çalıştırma" sayılmaz; encrypted artifact varken
/// key bulunamıyorsa yeni key üretmek yerine fail-closed kilitlenir.
enum HerculesMemoryVault {
    enum VaultError: LocalizedError {
        case keyUnavailable(OSStatus)
        case keyMissingForExistingVault
        case keyConflict
        case invalidKey
        case invalidEnvelope
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .keyUnavailable(let status):
                return "Hafıza anahtarına erişilemiyor (Keychain \(status))."
            case .keyMissingForExistingVault:
                return "Şifreli hafıza var ama cihaz anahtarı bulunamadı."
            case .keyConflict:
                return "Legacy ve Data Protection Keychain hafıza anahtarları birbiriyle çelişiyor."
            case .invalidKey:
                return "Hafıza anahtarı geçersiz."
            case .invalidEnvelope:
                return "Şifreli hafıza dosya formatı geçersiz."
            case .authenticationFailed:
                return "Şifreli hafızanın bütünlük doğrulaması başarısız."
            }
        }
    }

    private enum KeyRead {
        case found(Data)
        case notFound
        case conflict
        case failed(OSStatus)
    }

    private struct AcquiredKey {
        var key: SymmetricKey
        /// Only populated when this exact call successfully inserted the
        /// Data Protection Keychain item. Duplicate-item races are not owned.
        var createdRawKey: Data?
    }

    struct RestoreSealResult {
        var envelope: Data
        fileprivate var createdRawKey: Data?
    }

    enum RestoreKeyRollbackPlan: Equatable {
        case alreadyAbsent
        case deleteMatchingKey
        case conflict
    }

    enum MacKeyResolution: Equatable {
        case useDataProtection(Data, cleanupLegacy: Bool)
        case migrateLegacy(Data)
        case missing
        case conflict
    }

    private static let service = "hercules.memory"
    private static let account = "vault-key-v1"
    private static let magic = Data([0x48, 0x43, 0x4D, 0x56]) // HCMV
    private static let version: UInt8 = 1
    private static let lock = NSLock()

    static func seal(
        _ plaintext: Data,
        aad: String,
        allowKeyCreation: Bool
    ) throws -> Data {
        let key = try key(allowCreation: allowKeyCreation)
        return try seal(plaintext, aad: aad, using: key)
    }

    /// Restore may legitimately bootstrap a missing device key, but failed
    /// replace semantics must be able to put that missing-key state back.
    /// The raw key is an ownership token and never leaves this process/file.
    static func sealForRestore(_ plaintext: Data, aad: String) throws -> RestoreSealResult {
        let acquired = try acquireKey(allowCreation: true)
        do {
            return RestoreSealResult(
                envelope: try seal(plaintext, aad: aad, using: acquired.key),
                createdRawKey: acquired.createdRawKey
            )
        } catch {
            if let createdRawKey = acquired.createdRawKey {
                // Do not leak a newly-created key when sealing itself fails.
                try rollbackCreatedRestoreKey(createdRawKey)
            }
            throw error
        }
    }

    /// Ayrı crypto çekirdeği production Keychain yolunun yanı sıra bütünlük/AAD
    /// regresyon testlerinde sabit ephemeral key ile doğrulanabilir.
    static func seal(
        _ plaintext: Data,
        aad: String,
        using key: SymmetricKey
    ) throws -> Data {
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: Data(aad.utf8)
        )
        guard let combined = sealed.combined else { throw VaultError.invalidEnvelope }
        var output = magic
        output.append(version)
        output.append(combined)
        return output
    }

    static func open(_ envelope: Data, aad: String) throws -> Data {
        guard envelope.count > magic.count + 1,
              envelope.prefix(magic.count) == magic,
              envelope[magic.count] == version
        else { throw VaultError.invalidEnvelope }
        // Artifact zaten var: Keychain item gerçekten yoksa yeni anahtar üretme.
        let key = try key(allowCreation: false)
        return try open(envelope, aad: aad, using: key)
    }

    static func open(
        _ envelope: Data,
        aad: String,
        using key: SymmetricKey
    ) throws -> Data {
        guard envelope.count > magic.count + 1,
              envelope.prefix(magic.count) == magic,
              envelope[magic.count] == version
        else { throw VaultError.invalidEnvelope }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(envelope.dropFirst(magic.count + 1)))
            return try AES.GCM.open(box, using: key, authenticating: Data(aad.utf8))
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.authenticationFailed
        }
    }

    static func harden(_ url: URL) {
        HerculesFileHardening.hardenFile(url)
    }

    /// Eski sürümler okunamayan `agent-memory.json` dosyasını düz metin bir
    /// `agent-memory-unreadable-*.json` kopyasına alıyordu. Kurtarma değerini
    /// kaybetmeden bu kalıntıları opaque AES-GCM karantinasına taşır.
    ///
    /// Her dosya ancak atomic write + decrypt + byte-for-byte doğrulamadan sonra
    /// silinir. Var olan karantina farklıysa iki taraf da korunur ve hata yüzeye çıkar.
    static func quarantineLegacyMemoryBackups(in directory: URL) throws {
        let fm = FileManager.default
        let candidates = try hardenLegacyMemoryBackups(in: directory)
        for legacyURL in candidates {
            let name = legacyURL.lastPathComponent
            let values = try legacyURL.resourceValues(
                forKeys: [.fileSizeKey]
            )
            // Bir kurtarma dosyası normal hafıza snapshot'ının çok üstündeyse
            // sınırsız Data allocation yapma; dosyayı yerinde bırakıp uyar.
            guard (values.fileSize ?? 0) <= 64 * 1_024 * 1_024 else {
                throw VaultError.invalidEnvelope
            }

            let plaintext = try Data(contentsOf: legacyURL, options: [.mappedIfSafe])
            let quarantineURL = legacyURL
                .deletingPathExtension()
                .appendingPathExtension("herculesbox")
            let aad = "hercules.agent-memory.legacy-quarantine:v1:\(name)"

            if fm.fileExists(atPath: quarantineURL.path) {
                let targetValues = try quarantineURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard targetValues.isRegularFile == true, targetValues.isSymbolicLink != true else {
                    throw VaultError.invalidEnvelope
                }
                let existing = try Data(contentsOf: quarantineURL, options: [.mappedIfSafe])
                guard try open(existing, aad: aad) == plaintext else {
                    throw VaultError.authenticationFailed
                }
            } else {
                let envelope = try seal(plaintext, aad: aad, allowKeyCreation: false)
                try envelope.write(to: quarantineURL, options: [.atomic])
                harden(quarantineURL)
                let written = try Data(contentsOf: quarantineURL, options: [.mappedIfSafe])
                guard try open(written, aad: aad) == plaintext else {
                    throw VaultError.authenticationFailed
                }
            }

            harden(quarantineURL)
            try fm.removeItem(at: legacyURL)
        }
    }

    /// Harden every trustworthy plaintext candidate before attempting any
    /// multi-file migration. Thus a failure on one file cannot leave later
    /// recovery files with broad permissions or eligible for device backup.
    @discardableResult
    static func hardenLegacyMemoryBackups(in directory: URL) throws -> [URL] {
        let candidates = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var validated: [URL] = []
        var foundInvalidCandidate = false
        for legacyURL in candidates {
            let name = legacyURL.lastPathComponent
            guard name.hasPrefix("agent-memory-unreadable-"),
                  name.hasSuffix(".json")
            else { continue }

            let values: URLResourceValues
            do {
                values = try legacyURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                )
            } catch {
                // Keep scanning so later trustworthy candidates are still
                // hardened even if this directory entry raced or is unreadable.
                foundInvalidCandidate = true
                continue
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                foundInvalidCandidate = true
                continue
            }
            // Migration tamamlanamasa bile eski düz-metnin izinlerini hemen daralt
            // ve yeni bir cihaz yedeğine tekrar girmesini engelle.
            harden(legacyURL)
            validated.append(legacyURL)
        }
        guard !foundInvalidCandidate else { throw VaultError.invalidEnvelope }
        return validated
    }

    private static func key(allowCreation: Bool) throws -> SymmetricKey {
        try acquireKey(allowCreation: allowCreation).key
    }

    private static func acquireKey(allowCreation: Bool) throws -> AcquiredKey {
        lock.lock()
        defer { lock.unlock() }

        switch readKey() {
        case .found(let raw):
            guard raw.count == 32 else { throw VaultError.invalidKey }
            return AcquiredKey(key: SymmetricKey(data: raw), createdRawKey: nil)
        case .conflict:
            throw VaultError.keyConflict
        case .failed(let status):
            throw VaultError.keyUnavailable(status)
        case .notFound:
            guard allowCreation else { throw VaultError.keyMissingForExistingVault }
            let key = SymmetricKey(size: .bits256)
            let raw = key.withUnsafeBytes { Data($0) }
            var query = keychainIdentityQuery(useDataProtection: true)
            query[kSecValueData as String] = raw
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess {
                return AcquiredKey(key: key, createdRawKey: raw)
            }
            if status == errSecDuplicateItem,
               case .found(let existing) = readKey(),
               existing.count == 32 {
                return AcquiredKey(
                    key: SymmetricKey(data: existing),
                    createdRawKey: nil
                )
            }
            throw VaultError.keyUnavailable(status)
        }
    }

    static func restoreKeyRollbackPlan(
        createdKey: Data,
        currentKey: Data?
    ) -> RestoreKeyRollbackPlan {
        guard let currentKey else { return .alreadyAbsent }
        return currentKey == createdKey ? .deleteMatchingKey : .conflict
    }

    /// Delete only the exact Keychain value created by this restore. A missing
    /// item is already the desired rollback state; a different value indicates
    /// concurrent ownership and is never removed.
    static func rollbackCreatedRestoreKey(_ createdRawKey: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        let current: Data?
        switch readKey() {
        case .found(let raw):
            current = raw
        case .notFound:
            current = nil
        case .conflict:
            throw VaultError.keyConflict
        case .failed(let status):
            throw VaultError.keyUnavailable(status)
        }

        switch restoreKeyRollbackPlan(createdKey: createdRawKey, currentKey: current) {
        case .alreadyAbsent:
            return
        case .conflict:
            throw VaultError.keyConflict
        case .deleteMatchingKey:
            let status = SecItemDelete(
                keychainIdentityQuery(useDataProtection: true) as CFDictionary
            )
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw VaultError.keyUnavailable(status)
            }
        }
    }

    static func resolveMacKeys(
        dataProtection: Data?,
        legacy: Data?
    ) -> MacKeyResolution {
        switch (dataProtection, legacy) {
        case let (.some(dp), .some(old)):
            guard dp == old else { return .conflict }
            return .useDataProtection(dp, cleanupLegacy: true)
        case let (.some(dp), .none):
            return .useDataProtection(dp, cleanupLegacy: false)
        case let (.none, .some(old)):
            return .migrateLegacy(old)
        case (.none, .none):
            return .missing
        }
    }

    static func keychainIdentityQuery(useDataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        #if os(macOS)
        if useDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        #endif
        return query
    }

    private static func readKey() -> KeyRead {
        #if os(macOS)
        let dataProtectionRead = readRawKey(useDataProtection: true)
        let legacyRead = readRawKey(useDataProtection: false)
        if case .failed(let status) = dataProtectionRead { return .failed(status) }
        if case .failed(let status) = legacyRead { return .failed(status) }

        let dataProtectionData: Data?
        if case .found(let data) = dataProtectionRead {
            dataProtectionData = data
        } else {
            dataProtectionData = nil
        }
        let legacyData: Data?
        if case .found(let data) = legacyRead {
            legacyData = data
        } else {
            legacyData = nil
        }

        switch resolveMacKeys(dataProtection: dataProtectionData, legacy: legacyData) {
        case .missing:
            return .notFound
        case .conflict:
            return .conflict
        case .useDataProtection(let data, let cleanupLegacy):
            // Bozuk bir değeri migrate/cleanup ederek tek kurtarma kopyasını yok etme.
            guard data.count == 32 else { return .found(data) }
            if cleanupLegacy {
                let status = SecItemDelete(
                    keychainIdentityQuery(useDataProtection: false) as CFDictionary
                )
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    return .failed(status)
                }
            }
            return .found(data)
        case .migrateLegacy(let data):
            // Geçersiz uzunluğu yeni namespace'e taşımadan üst katmanın invalidKey
            // durumunu raporlamasına izin ver; legacy kurtarma değeri yerinde kalır.
            guard data.count == 32 else { return .found(data) }
            var add = keychainIdentityQuery(useDataProtection: true)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
                return .failed(addStatus)
            }

            // Atomic namespace move API'si yok: önce DP kaydını tekrar okuyup exact
            // byte eşitliğini doğrula, ancak ondan sonra legacy kaydı kaldır.
            switch readRawKey(useDataProtection: true) {
            case .found(let verified) where verified == data:
                break
            case .found:
                return .conflict
            case .failed(let status):
                return .failed(status)
            case .notFound, .conflict:
                return .failed(errSecItemNotFound)
            }

            let deleteStatus = SecItemDelete(
                keychainIdentityQuery(useDataProtection: false) as CFDictionary
            )
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                return .failed(deleteStatus)
            }
            return .found(data)
        }
        #else
        return readRawKey(useDataProtection: false)
        #endif
    }

    private static func readRawKey(useDataProtection: Bool) -> KeyRead {
        var query = keychainIdentityQuery(useDataProtection: useDataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .failed(errSecDecode) }
            return .found(data)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed(status)
        }
    }
}

struct MemoryEmbeddingCandidate: Sendable {
    var id: UUID
    var content: String
    var updatedAt: Date
}

struct MemoryEmbeddingUpdate: Sendable {
    var id: UUID
    var expectedContent: String
    var expectedUpdatedAt: Date
    var vector: [Float]
}

enum LocalMemoryStorageState: Equatable {
    case ready
    case writeFailed(String)
    case locked(String)
    case corrupt(String)
    case conflict(String)

    var issue: String? {
        switch self {
        case .ready: return nil
        case .writeFailed(let message),
             .locked(let message),
             .corrupt(let message),
             .conflict(let message):
            return message
        }
    }

    var allowsMutation: Bool {
        switch self {
        case .ready, .writeFailed: return true
        case .locked, .corrupt, .conflict: return false
        }
    }
}

enum LocalMemoryRestoreError: LocalizedError, Equatable {
    case persistenceFailed(String)
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let message):
            return "Hafıza geri yüklemesi diske güvenli biçimde yazılamadı. \(message)"
        case .rollbackFailed(let message):
            return "Hafıza geri yüklemesi başarısız oldu ve eski disk kopyası geri konamadı. \(message)"
        }
    }
}

/// Centralizes retention transitions so automatic expiry/decay preserve the
/// temporal record and invalidate any stale compare-and-swap revision.
enum LocalMemoryInvalidationPolicy {
    private static let minimumRevisionStep: TimeInterval = 0.000_001

    @discardableResult
    static func softInvalidate(_ memory: inout AgentMemory, at now: Date) -> Bool {
        guard memory.isActive else { return false }
        memory.invalidatedAt = now
        memory.updatedAt = max(
            now,
            memory.updatedAt.addingTimeInterval(minimumRevisionStep)
        )
        return true
    }

    @discardableResult
    static func softInvalidateIfExpired(
        _ memory: inout AgentMemory,
        now: Date
    ) -> Bool {
        guard !memory.pinned,
              let expiresAt = memory.expiresAt,
              expiresAt < now
        else { return false }
        return softInvalidate(&memory, at: now)
    }

    @discardableResult
    static func softInvalidateForDecayIfNeeded(
        _ memory: inout AgentMemory,
        unseenDays: Double,
        now: Date
    ) -> Bool {
        guard memory.importance <= 0.25, unseenDays > 180 else { return false }
        return softInvalidate(&memory, at: now)
    }
}

/// Reload ile arka-plan dosya yazımının son atomik commit bölümünü sıralar.
///
/// Actor sequence'i kuyruktaki eski işleri eler; bu kapı ise halihazırda encode
/// edilmiş bir snapshot'ın reload tamamlandıktan sonra diske düşmesini engeller.
/// `invalidate()` aktif commit bitene kadar bekler ve nesli senkron artırır:
/// dolayısıyla dönüşünden sonra eski nesilden hiçbir iş diske dokunamaz.
final class LocalMemoryWriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0

    func currentGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    @discardableResult
    func invalidate() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    func performIfCurrent<T>(
        generation expectedGeneration: UInt64,
        _ operation: () throws -> T
    ) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expectedGeneration else { return nil }
        return try operation()
    }
}

enum AutomaticMemoryBulkPolicy {
    static func mayBegin(isCancelled: Bool, generationMatches: Bool) -> Bool {
        !isCancelled && generationMatches
    }

    static func mayContinueDurableWait(
        isCancelled: Bool,
        ignoreCancellation: Bool,
        writeGenerationMatches: Bool
    ) -> Bool {
        writeGenerationMatches && (ignoreCancellation || !isCancelled)
    }
}

@MainActor
final class LocalMemoryProvider {
    static let shared = LocalMemoryProvider()

    /// Uzun süren extraction/backfill işi kullanıcı hafızayı sildikten veya elle
    /// düzenledikten sonra eski snapshot'ı diske dahi commit edemez. Kilit yalnız
    /// generation karşılaştırmasını değil son atomic commit bölümünü de kapsar;
    /// `invalidate()` döndüğünde eski neslin aktif commit'i kalmamıştır.
    final class AutomaticWriteGate: @unchecked Sendable {
        private let lock = NSLock()
        private var generation: UInt64 = 0

        func currentGeneration() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            return generation
        }

        @discardableResult
        func invalidate() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            generation &+= 1
            return generation
        }

        func permits(_ expectedGeneration: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return generation == expectedGeneration
        }

        func performIfCurrent<T>(
            generation expectedGeneration: UInt64,
            _ operation: () throws -> T
        ) rethrows -> T? {
            lock.lock()
            defer { lock.unlock() }
            guard generation == expectedGeneration else { return nil }
            return try operation()
        }
    }

    private struct MemoryPayload: Codable, Sendable {
        var version: Int
        var savedAt: Date
        var memories: [AgentMemory]
    }

    private struct DiskFingerprint: Equatable {
        var exists: Bool
        var modificationDate: Date?
        var fileSize: Int?
    }

    private struct MemoryWriteResult: Sendable {
        var succeeded: Bool
        var message: String?
        /// Ownership token for a Keychain value created specifically by a
        /// restore write. It is returned even when the write becomes stale.
        var createdRestoreKey: Data? = nil
    }

    /// Disk yazımlarını serialize eder ve encode'u main thread'den çıkarır.
    /// sequence sırasına göre yazar; eski (stale) yazımları atlar.
    private actor MemoryFileWriter {
        private var latest = 0
        private let encoder: JSONEncoder = {
            let e = JSONEncoder()
            // Double seconds preserve Date's sub-second value exactly across a
            // portable restore; decodePayload remains backward-compatible with
            // the older ISO-8601 on-device payload.
            e.dateEncodingStrategy = .secondsSince1970
            // .sortedKeys determinizm için; .prettyPrinted şifreli blob'da yalnız
            // boyut/encode maliyeti şişiriyordu.
            e.outputFormatting = [.sortedKeys]
            return e
        }()

        /// Bu sequence'e kadar olan uçuştaki yazımları geçersiz kıl (restore sonrası stale write'ı diske vurmadan engeller).
        func invalidate(upTo sequence: Int) { latest = max(latest, sequence) }

        func quarantineLegacyBackups(in directory: URL) -> String? {
            do {
                try HerculesMemoryVault.quarantineLegacyMemoryBackups(in: directory)
                return nil
            } catch {
                return error.localizedDescription
            }
        }

        private func commitIfCurrent(
            generation: UInt64,
            gate: LocalMemoryWriteGate,
            automaticGeneration: UInt64?,
            automaticGate: AutomaticWriteGate,
            _ operation: () -> MemoryWriteResult
        ) -> MemoryWriteResult {
            let stale = MemoryWriteResult(succeeded: false, message: nil)
            guard let automaticGeneration else {
                return gate.performIfCurrent(
                    generation: generation,
                    operation
                ) ?? stale
            }

            // Lock sırası her writer'da writeGate → automaticGate. Manuel bir
            // mutation automaticGate.invalidate() döndüğünde bu eski commit ya
            // tamamlanmıştır ya da artık başlayamaz.
            guard let automaticResult = gate.performIfCurrent(generation: generation, {
                automaticGate.performIfCurrent(
                    generation: automaticGeneration,
                    operation
                )
            }) else { return stale }
            return automaticResult ?? stale
        }

        @discardableResult
        func write(
            payload: MemoryPayload?,
            to url: URL,
            sequence: Int,
            generation: UInt64,
            gate: LocalMemoryWriteGate,
            automaticGeneration: UInt64?,
            automaticGate: AutomaticWriteGate,
            forceKeyCreation: Bool = false
        ) -> MemoryWriteResult {
            guard sequence >= latest else {
                return MemoryWriteResult(succeeded: false, message: nil)
            }
            latest = sequence
            guard let payload else {
                return commitIfCurrent(
                    generation: generation,
                    gate: gate,
                    automaticGeneration: automaticGeneration,
                    automaticGate: automaticGate
                ) {
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        return MemoryWriteResult(succeeded: true, message: nil)
                    }
                    do {
                        try FileManager.default.removeItem(at: url)
                        try LocalMemoryProvider.synchronizeDirectory(
                            url.deletingLastPathComponent()
                        )
                        return MemoryWriteResult(succeeded: true, message: nil)
                    } catch {
                        return MemoryWriteResult(succeeded: false, message: error.localizedDescription)
                    }
                }
            }
            do {
                let plaintext = try encoder.encode(payload)
                let envelope: Data
                let createdRestoreKey: Data?
                if forceKeyCreation {
                    let sealed = try HerculesMemoryVault.sealForRestore(
                        plaintext,
                        aad: LocalMemoryProvider.memoryAAD
                    )
                    envelope = sealed.envelope
                    createdRestoreKey = sealed.createdRawKey
                } else {
                    envelope = try HerculesMemoryVault.seal(
                        plaintext,
                        aad: LocalMemoryProvider.memoryAAD,
                        allowKeyCreation: !FileManager.default.fileExists(atPath: url.path)
                    )
                    createdRestoreKey = nil
                }
                var result = commitIfCurrent(
                    generation: generation,
                    gate: gate,
                    automaticGeneration: automaticGeneration,
                    automaticGate: automaticGate
                ) {
                    do {
                        try envelope.write(to: url, options: [.atomic])
                        HerculesMemoryVault.harden(url)
                        try LocalMemoryProvider.synchronizeFileAndDirectory(url)

                        // Atomic write tek başına yeterli değil: migration plaintext'i ancak
                        // diskteki ciphertext tekrar açılıp byte-byte doğrulanırsa silebilir.
                        let written = try Data(contentsOf: url)
                        let verified = try HerculesMemoryVault.open(
                            written,
                            aad: LocalMemoryProvider.memoryAAD
                        )
                        guard verified == plaintext else {
                            return MemoryWriteResult(
                                succeeded: false,
                                message: "Şifreli hafıza yazım doğrulaması eşleşmedi."
                            )
                        }
                        // A restore-created key is still provisional here. Do
                        // not migrate other files under it until restore has
                        // passed canonical verification and retained the key.
                        if !forceKeyCreation {
                            try HerculesMemoryVault.quarantineLegacyMemoryBackups(
                                in: url.deletingLastPathComponent()
                            )
                        }
                        return MemoryWriteResult(succeeded: true, message: nil)
                    } catch {
                        return MemoryWriteResult(succeeded: false, message: error.localizedDescription)
                    }
                }
                // Sealing/key acquisition happens before the gated filesystem
                // commit, so stale-generation results must retain this token.
                result.createdRestoreKey = createdRestoreKey
                return result
            } catch {
                return MemoryWriteResult(succeeded: false, message: error.localizedDescription)
            }
        }
    }

    private let memoryURL: URL
    private let legacyMemoryURL: URL
    private var memories: [AgentMemory] = []
    private var memoryTermsByID: [UUID: Set<String>] = [:]
    private var memoryTagTermsByID: [UUID: Set<String>] = [:]
    /// normalizedMemoryKey → id: upsert dedup'u için. Eski hali her upsert'te TÜM
    /// corpus'u yeniden tokenize ediyordu (launch backfill'inde yüzlerce çift × N kayıt).
    private var memoryKeyToID: [String: UUID] = [:]
    private var loadedFingerprint: DiskFingerprint?
    private var writeSequence = 0
    private var deferredWriteInFlight = false
    private var latestWriteTask: Task<MemoryWriteResult, Never>?
    private var latestWriteTaskSequence: Int?
    private var completedWriteSequence = 0
    private var completedWriteSucceeded = false
    private var pendingLegacyCleanup = false
    private(set) var storageState: LocalMemoryStorageState = .ready
    private let automaticWriteGate = AutomaticWriteGate()
    private let fileWriter = MemoryFileWriter()
    private let writeGate = LocalMemoryWriteGate()
    nonisolated fileprivate static let memoryAAD = "hercules.agent-memory:v2"

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let preciseDateDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private init() {
        let urls = Self.makeMemoryURLs()
        memoryURL = urls.encrypted
        legacyMemoryURL = urls.legacy
        reloadFromDisk()
    }

    var storageIssue: String? { storageState.issue }
    /// `.writeFailed` still has a usable canonical RAM snapshot. UI may warn,
    /// but editing and portable export remain valuable recovery operations.
    var storageAllowsMutation: Bool { storageState.allowsMutation }
    var canExportPortableArchive: Bool { storageState.allowsMutation }
    var automaticWriteGeneration: UInt64 { automaticWriteGate.currentGeneration() }

    func reloadFromDisk() {
        automaticWriteGate.invalidate()
        cancelDeferredWrite()
        load()
        if storageState.allowsMutation, pruneExpiredMemories() {
            persist()
        }
    }

    func search(query: String, topK: Int) -> [AgentMemory] {
        refreshFromDiskIfChanged()
        if storageState.allowsMutation, pruneExpiredMemories() {
            persist()
        }
        let queryTerms = Set(Self.tokens(query))
        guard !queryTerms.isEmpty else { return [] }

        let now = Date()
        let scored = memories
            .filter { $0.isActive && !Self.isExpired($0, now: now) }
            .map { memory -> (memory: AgentMemory, score: Double) in
                let memoryTerms = memoryTermsByID[memory.id] ?? Set(Self.tokens(memory.content + " " + memory.tags.joined(separator: " ")))
                let tagTerms = memoryTagTermsByID[memory.id] ?? Set(memory.tags.flatMap(Self.tokens))
                let overlap = queryTerms.intersection(memoryTerms)
                let tagOverlap = queryTerms.intersection(tagTerms)
                let recencyDays = max(0, now.timeIntervalSince(memory.updatedAt) / 86_400)
                let recency = 1.0 / (1.0 + min(recencyDays, 60))
                let score = Double(overlap.count) * 2.0
                    + Double(tagOverlap.count) * 3.0
                    + memory.confidence
                    + memory.importance
                    + recency
                    + (memory.pinned ? 2.0 : 0.0)
                return (memory, score)
            }
            .filter { $0.score >= 2.0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.memory.updatedAt > rhs.memory.updatedAt
                }
                return lhs.score > rhs.score
            }

        let selected = Array(scored.prefix(topK)).map(\.memory)
        touch(selected)
        return selected
    }

    func allMemories(includeInvalidated: Bool = false) -> [AgentMemory] {
        refreshFromDiskIfChanged()
        if storageState.allowsMutation, pruneExpiredMemories() {
            persist()
        }
        return memories
            .filter { includeInvalidated || $0.isActive }
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned {
                    return lhs.pinned && !rhs.pinned
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    /// Explicit portable-archive restore. This is deliberately replace semantics:
    /// the caller must obtain user confirmation before calling it.
    ///
    /// Incoming records are fully validated before any generation or RAM mutation.
    /// Once begun, old automatic/background writers are invalidated, the complete
    /// snapshot (including invalidated history) is committed and read-back verified,
    /// and success is returned only after file + directory durability barriers. Any
    /// failure restores both the previous RAM state and the exact prior disk bytes.
    @discardableResult
    func replaceAllMemoriesDurably(with restored: [AgentMemory]) async throws -> Int {
        try HerculesMemoryArchive.validateForRestore(restored)

        if storageState == .ready {
            refreshFromDiskIfChanged()
        }

        // Önce eski otomatik mutation/commit yetkisini düşür; writeGate.invalidate()
        // o anda commit bölümüne girmiş writer bitmeden dönmez. Actor barrier'ı da
        // kuyruktaki encode işlerini eledikten SONRA rollback snapshot'ı alınır.
        automaticWriteGate.invalidate()
        cancelDeferredWrite()
        let barrier = writeSequence
        await fileWriter.invalidate(upTo: barrier)

        let oldEncrypted = try Self.captureRawFile(memoryURL)
        let oldLegacy = try Self.captureRawFile(legacyMemoryURL)
        let oldStorageState = storageState
        let oldMemories = try Self.rollbackMemories(
            encrypted: oldEncrypted,
            legacy: oldLegacy,
            storageState: oldStorageState,
            fallback: memories
        )
        let oldPendingLegacyCleanup = pendingLegacyCleanup

        memories = restored
        storageState = .ready
        pendingLegacyCleanup = oldLegacy != nil
        rebuildSearchIndex()
        persist(forceKeyCreation: true)

        // Retain this exact task/result: a later sequence must not hide the
        // restore-owned Keychain token needed by rollback.
        let restoreWriteTask = latestWriteTask
        let restoreWriteSequence = latestWriteTaskSequence
        let restoreWriteResult = await restoreWriteTask?.value
        let persisted = restoreWriteResult?.succeeded == true
            && restoreWriteSequence != nil
            && writeSequence == restoreWriteSequence
            && completedWriteSequence == restoreWriteSequence
            && completedWriteSucceeded
        let canonicalReady = persisted
            && storageState == .ready
            && !FileManager.default.fileExists(atPath: legacyMemoryURL.path)
            && Self.persistedSnapshot(restored, matches: memoryURL)
        guard canonicalReady else {
            let failure = storageState.issue ?? "Doğrulanmış kalıcı yazım tamamlanmadı."
            cancelDeferredWrite()
            await fileWriter.invalidate(upTo: writeSequence)

            var rollbackFailures: [String] = []
            do {
                try Self.restoreRawFile(oldEncrypted, to: memoryURL)
                try Self.restoreRawFile(oldLegacy, to: legacyMemoryURL)
            } catch {
                rollbackFailures.append(error.localizedDescription)
            }
            if let createdRestoreKey = restoreWriteResult?.createdRestoreKey {
                do {
                    try HerculesMemoryVault.rollbackCreatedRestoreKey(createdRestoreKey)
                } catch {
                    rollbackFailures.append(
                        "Yeni hafıza anahtarı geri alınamadı: \(error.localizedDescription)"
                    )
                }
            }

            memories = oldMemories
            storageState = oldStorageState
            pendingLegacyCleanup = oldPendingLegacyCleanup
            loadedFingerprint = Self.diskFingerprint(for: memoryURL)
            rebuildSearchIndex()
            postLocalMemoryChanged()

            if !rollbackFailures.isEmpty {
                throw LocalMemoryRestoreError.rollbackFailed(
                    rollbackFailures.joined(separator: " ")
                )
            }
            throw LocalMemoryRestoreError.persistenceFailed(failure)
        }

        loadedFingerprint = Self.diskFingerprint(for: memoryURL)
        pendingLegacyCleanup = false
        // The restore snapshot is now canonical and its key (if newly
        // created) is retained, so partial quarantine cannot be orphaned by
        // restore rollback. Keep the multi-file I/O off the main actor and
        // serialized with normal memory-file writes.
        if let cleanupFailure = await fileWriter.quarantineLegacyBackups(
            in: memoryURL.deletingLastPathComponent()
        ) {
            storageState = .writeFailed(
                "Hafıza geri yüklendi ancak eski düz-metin kurtarma yedekleri "
                    + "şifreli karantinaya taşınamadı. Dosyalar sıkı izinlerle "
                    + "cihaz yedeği dışında tutuluyor. \(cleanupFailure)"
            )
        }
        postLocalMemoryChanged()
        return restored.count
    }

    /// Kilitli/bozuk kasayı kenara alıp çalışan boş bir kasa açar.
    ///
    /// Cihaz anahtarı kaybolduğunda AES-GCM zarfı MATEMATİKSEL olarak açılamaz;
    /// kilit kalıcıdır ve sayfa aksi halde kalıcı bir çıkmazda kalır. Yine de
    /// dosya SİLİNMEZ: zaman damgalı bir kopyaya taşınır, böylece anahtar ya da
    /// bir yedek sonradan çıkarsa ciphertext hâlâ diskte durur.
    ///
    /// Eski düz-metin dosyaya dokunulmaz — varsa `load()` onu migrate eder ve
    /// kayıtlar geri gelir; sıfırlama o durumda veri kaybı değil kurtarmadır.
    @discardableResult
    func resetLockedVault() async throws -> URL? {
        guard !storageState.allowsMutation else { return nil }

        // Sıfırlama diskteki dosyayı yerinden oynatıyor: eski nesil writer'ların
        // taşınmış kasaya yazma yetkisini önce düşür.
        automaticWriteGate.invalidate()
        cancelDeferredWrite()
        await fileWriter.invalidate(upTo: writeSequence)

        var archivedURL: URL?
        let fm = FileManager.default
        if fm.fileExists(atPath: memoryURL.path) {
            let target = Self.orphanedVaultURL(for: memoryURL)
            try fm.moveItem(at: memoryURL, to: target)
            HerculesMemoryVault.harden(target)
            try Self.synchronizeDirectory(memoryURL.deletingLastPathComponent())
            archivedURL = target
        }

        memories = []
        pendingLegacyCleanup = false
        loadedFingerprint = nil
        storageState = .ready
        // load() diski yeniden okur: düz-metin kalıntı varsa migrate eder,
        // yoksa boş + .ready ile açılır ve ilk yazım yeni anahtarı üretir.
        load()
        postLocalMemoryChanged()
        return archivedURL
    }

    /// `agent-memory-kilitli-20260826-0312.herculesbox` — aynı saniyede ikinci bir
    /// sıfırlama olursa sayaçla ayrışır, var olan bir kopyanın üstüne asla yazılmaz.
    private static func orphanedVaultURL(for url: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: .now)
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        var candidate = dir.appendingPathComponent("agent-memory-kilitli-\(stamp).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("agent-memory-kilitli-\(stamp)-\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }

    /// Coach context'ine enjekte edilecek memory seti. Küçük bir canonical çekirdek
    /// + gerçekten alakalı hybrid sonuçlar döner. `limit` KATI tavandır; çok sayıda
    /// core/pin kaydı prompt bütçesini aşamaz.
    func contextMemories(query: String, queryEmbedding: [Float]? = nil, limit: Int = 16) -> [AgentMemory] {
        refreshFromDiskIfChanged()
        if storageState.allowsMutation, pruneExpiredMemories() { persist() }
        let hardLimit = min(max(0, limit), 32)
        guard hardLimit > 0 else { return [] }
        let now = Date()
        let active = Self.modelSafeMemories(
            memories.filter { $0.isActive && !Self.isExpired($0, now: now) }
        )
        guard !active.isEmpty else { return [] }

        let queryTerms = Set(Self.tokens(query))
        func relevance(_ memory: AgentMemory) -> (score: Double, hasSignal: Bool) {
            let terms = memoryTermsByID[memory.id] ?? Set(Self.tokens(memory.content + " " + memory.tags.joined(separator: " ")))
            let tagTerms = memoryTagTermsByID[memory.id] ?? Set(memory.tags.flatMap(Self.tokens))
            let overlapCount = queryTerms.intersection(terms).count
            let tagOverlap = queryTerms.intersection(tagTerms).count
            let lexical = queryTerms.isEmpty
                ? 0
                : min(1.0, Double(overlapCount + tagOverlap) / Double(queryTerms.count))
            let freshnessDays = max(0, now.timeIntervalSince(memory.updatedAt) / 86_400)
            let freshness = 1.0 / (1.0 + freshnessDays / 120.0)
            var semantic = 0.0
            if let queryEmbedding,
               memory.embeddingModel == EmbeddingService.modelID,
               let emb = memory.embedding,
               !emb.isEmpty {
                let cosine = Double(EmbeddingMath.cosine(queryEmbedding, emb))
                if cosine >= 0.28 { semantic = cosine }
            }
            let score = semantic * 0.56
                + lexical * 0.24
                + memory.importance * 0.11
                + memory.confidence * 0.06
                + freshness * 0.03
            return (score, semantic > 0 || overlapCount > 0 || tagOverlap > 0)
        }

        func corePriority(_ memory: AgentMemory) -> Int {
            if memory.pinned { return 5 }
            switch memory.type {
            case .constraint: return 4
            case .goal: return 3
            case .profile: return 2
            default: return 0
            }
        }

        // Always-visible blok kasıtlı olarak küçüktür (Letta/core-memory yaklaşımı).
        let canonicalLimit = min(hardLimit, 10)
        let canonical = active
            .filter { $0.type.isCore || $0.pinned }
            .sorted { lhs, rhs in
                let lp = corePriority(lhs), rp = corePriority(rhs)
                if lp != rp { return lp > rp }
                if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(canonicalLimit)
            .map { $0 }

        // Ham cosine ve lexical sayıları aynı ölçekte değildir; önce her sinyali
        // normalize edip sonra bounded blend uygula. Sinyalsiz kayıt enjekte edilmez.
        let rest = active
            .filter { !($0.type.isCore || $0.pinned) }
            .map { memory -> (memory: AgentMemory, score: Double, hasSignal: Bool) in
                let ranked = relevance(memory)
                return (memory, ranked.score, ranked.hasSignal)
            }
            .filter(\.hasSignal)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.memory.updatedAt > rhs.memory.updatedAt }
                return lhs.score > rhs.score
            }
            .map(\.memory)
        let remaining = max(0, hardLimit - canonical.count)
        let selected = Array(canonical) + Array(rest.prefix(remaining))

        touch(selected)

        return selected.sorted { lhs, rhs in
            if lhs.type.isCore != rhs.type.isCore { return lhs.type.isCore && !rhs.type.isCore }
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// LLM memory-manager'a verilecek "ilgili mevcut kayıtlar" kümesi. Çekirdek
    /// (profil/hedef/kısıt) + pinli kayıtlar her zaman dahil; gerisi konuşmaya
    /// lexical alaka skoruyla seçilir. Yan etkisiz — lastSeenAt'e dokunmaz, persist etmez.
    func candidatesForUpdate(userText: String, assistantText: String, limit: Int = 12) -> [AgentMemory] {
        refreshFromDiskIfChanged()
        let now = Date()
        let active = Self.modelSafeMemories(
            memories.filter { $0.isActive && !Self.isExpired($0, now: now) }
        )
        guard !active.isEmpty else { return [] }

        // Assistant cevabı gerçek kullanıcı kanıtı değildir; candidate retrieval'ı
        // onun olası halüsinasyonlarıyla genişletme.
        let queryTerms = Set(Self.tokens(userText))
        let scored = active.map { memory -> (memory: AgentMemory, score: Double) in
            let memoryTerms = memoryTermsByID[memory.id] ?? Set(Self.tokens(memory.content + " " + memory.tags.joined(separator: " ")))
            var score = Double(queryTerms.intersection(memoryTerms).count)
            if memory.type.isCore { score += 1.5 }
            if memory.pinned { score += 1.0 }
            return (memory, score)
        }

        return scored
            .filter { $0.score > 0 || $0.memory.type.isCore || $0.memory.pinned }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.memory.updatedAt > rhs.memory.updatedAt }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.memory)
    }

    /// Lokal decay (ağ yok): yalnız düşük-riskli episodic/other otomatik kayıtların
    /// retrieval önemini 30 günlük DİLİMLERLE azaltır. `lastDecayedAt` sayesinde aynı
    /// gün kaç sohbet olursa olsun bir kez uygulanır. Truth confidence düşürülmez.
    @discardableResult
    func applyDecay(now: Date = Date()) -> Bool {
        guard prepareForMutation() else { return false }
        let interval: TimeInterval = 30 * 86_400
        var changed = false
        for idx in memories.indices {
            let memory = memories[idx]
            guard memory.isActive, !memory.pinned, !memory.type.isCore,
                  Self.isAutoSource(memory.source),
                  memory.type == .episodic || memory.type == .other
            else { continue }
            let unseenDays = now.timeIntervalSince(memory.lastSeenAt) / 86_400
            guard unseenDays > 30 else { continue }
            let evidenceAnchor = max(memory.lastSeenAt, memory.updatedAt)
            let checkpoint = max(memory.lastDecayedAt ?? evidenceAnchor, evidenceAnchor)
            let elapsed = now.timeIntervalSince(checkpoint)
            let periods = Int(elapsed / interval)
            guard periods > 0 else { continue }
            memories[idx].importance = max(0.2, memory.importance - Double(periods) * 0.05)
            memories[idx].lastDecayedAt = checkpoint.addingTimeInterval(Double(periods) * interval)
            changed = true
            LocalMemoryInvalidationPolicy.softInvalidateForDecayIfNeeded(
                &memories[idx],
                unseenDays: unseenDays,
                now: now
            )
        }
        if changed {
            rebuildSearchIndex()
            persist()
        }
        return changed
    }

    /// Mem0 tarzı operasyon listesini uygula. UPDATE içerikte yerinde düzeltme;
    /// DELETE soft-invalidate (Zep tarzı, diskte kalır); ADD yeni kayıt (gerekirse
    /// eski kaydı supersede eder). Pinli/manuel kayıtlar LLM tarafından değiştirilemez/silinemez.
    @discardableResult
    func applyLLMOperations(
        _ ops: [LLMMemoryOperation],
        expectedAutomaticWriteGeneration: UInt64
    ) -> Int {
        guard !ops.isEmpty,
              automaticWriteGate.permits(expectedAutomaticWriteGeneration),
              prepareForMutation(),
              // prepareForMutation dış disk değişikliği görürse nesli ilerletebilir.
              automaticWriteGate.permits(expectedAutomaticWriteGeneration)
        else { return 0 }
        var changed = 0
        for op in ops {
            switch op.kind {
            case .add:
                guard let content = Self.cleanedContent(op.content),
                      !Self.shouldRejectAutomaticMemory(
                          ([content] + op.tags).joined(separator: " ")
                      )
                else { continue }
                var validatedSupersededIndex: Int?
                if let supersedes = op.supersedes {
                    guard let oldIdx = memories.firstIndex(where: { $0.id == supersedes }),
                          memories[oldIdx].isActive,
                          !memories[oldIdx].pinned,
                          !Self.isUserManagedSource(memories[oldIdx].source),
                          let expectedUpdatedAt = op.expectedUpdatedAt,
                          memories[oldIdx].updatedAt == expectedUpdatedAt
                    else {
                        // ADD+supersedes tek atomik niyettir. CAS geçmediyse çelişen
                        // yeni kaydı da yaratma.
                        continue
                    }
                    validatedSupersededIndex = oldIdx
                }
                let memory = upsertMemory(
                    content: content,
                    tags: op.tags,
                    source: "llm-add",
                    confidence: Self.bounded(op.confidence, default: 0.88, minimum: 0.5),
                    importance: Self.bounded(
                        op.importance,
                        default: AgentMemory.defaultImportance(for: op.type ?? .other),
                        minimum: 0.2
                    ),
                    type: op.type ?? .other
                )
                if let oldIdx = validatedSupersededIndex,
                   memories[oldIdx].id != memory.id {
                    memories[oldIdx].invalidatedAt = .now
                    memories[oldIdx].supersededBy = memory.id
                    memories[oldIdx].updatedAt = .now
                }
                changed += 1
            case .update:
                guard let id = op.targetID,
                      let idx = memories.firstIndex(where: { $0.id == id }),
                      !memories[idx].pinned,
                      !Self.isUserManagedSource(memories[idx].source),
                      let expectedUpdatedAt = op.expectedUpdatedAt,
                      memories[idx].updatedAt == expectedUpdatedAt,
                      let content = Self.cleanedContent(op.content),
                      !Self.shouldRejectAutomaticMemory(
                          ([content] + op.tags).joined(separator: " ")
                      )
                else { continue }
                memories[idx].content = content
                if !op.tags.isEmpty {
                    memories[idx].tags = Self.normalizedTags(memories[idx].tags + op.tags)
                }
                if let type = op.type, type != .other { memories[idx].type = type }
                memories[idx].importance = Self.bounded(
                    op.importance,
                    default: memories[idx].importance,
                    minimum: 0.2
                )
                memories[idx].confidence = Self.bounded(
                    op.confidence,
                    default: memories[idx].confidence,
                    minimum: 0.5
                )
                memories[idx].source = "llm-update"
                memories[idx].updatedAt = .now
                memories[idx].lastSeenAt = .now
                memories[idx].lastDecayedAt = nil
                memories[idx].invalidatedAt = nil
                memories[idx].supersededBy = nil
                memories[idx].embedding = nil          // içerik değişti → embedding bayat, yeniden hesaplanacak
                memories[idx].embeddingModel = nil
                changed += 1
            case .delete:
                guard let id = op.targetID,
                      let idx = memories.firstIndex(where: { $0.id == id }),
                      !memories[idx].pinned,
                      !Self.isUserManagedSource(memories[idx].source),
                      let expectedUpdatedAt = op.expectedUpdatedAt,
                      memories[idx].updatedAt == expectedUpdatedAt,
                      memories[idx].isActive
                else { continue }
                memories[idx].invalidatedAt = .now
                memories[idx].updatedAt = .now
                changed += 1
            }
        }
        if changed > 0 {
            rebuildSearchIndex()
            persist(expectedAutomaticWriteGeneration: expectedAutomaticWriteGeneration)
        }
        return changed
    }

    /// Embedding'i eksik veya güncel-model ile üretilmemiş aktif kayıtlar (backfill kaynağı).
    func memoriesNeedingEmbedding(model: String, limit: Int = 64) -> [MemoryEmbeddingCandidate] {
        refreshFromDiskIfChanged()
        return memories
            .filter { $0.isActive && ($0.embedding == nil || $0.embeddingModel != model) }
            .prefix(limit)
            .map { MemoryEmbeddingCandidate(id: $0.id, content: $0.content, updatedAt: $0.updatedAt) }
    }

    /// Embedding'i eksik/bayat aktif kayıt sayısı (backfill ilerlemesi için).
    func pendingEmbeddingCount(model: String) -> Int {
        refreshFromDiskIfChanged()
        return memories.filter { $0.isActive && ($0.embedding == nil || $0.embeddingModel != model) }.count
    }

    /// Hesaplanmış embedding'leri uygula (tek persist; arama indeksini etkilemez).
    func applyEmbeddings(_ updates: [MemoryEmbeddingUpdate], model: String) {
        guard !updates.isEmpty, prepareForMutation() else { return }
        let updatesByID = Dictionary(updates.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var changed = false
        for idx in memories.indices {
            guard let update = updatesByID[memories[idx].id],
                  memories[idx].isActive,
                  memories[idx].content == update.expectedContent,
                  memories[idx].updatedAt == update.expectedUpdatedAt,
                  update.vector.count == EmbeddingService.dimension,
                  update.vector.allSatisfy(\.isFinite)
            else { continue }
                memories[idx].embedding = update.vector
                memories[idx].embeddingModel = model
                changed = true
        }
        if changed { persist() }
    }

    func deleteMemory(id: UUID) {
        guard prepareForMutation(),
              let idx = memories.firstIndex(where: { $0.id == id })
        else { return }
        automaticWriteGate.invalidate()
        memories.remove(at: idx)
        rebuildSearchIndex()
        persist()
    }

    func setPinned(id: UUID, pinned: Bool) {
        guard prepareForMutation() else { return }
        guard let idx = memories.firstIndex(where: { $0.id == id }),
              memories[idx].pinned != pinned
        else { return }
        automaticWriteGate.invalidate()
        memories[idx].pinned = pinned
        memories[idx].updatedAt = .now
        memories[idx].lastSeenAt = .now
        memories[idx].lastDecayedAt = nil
        if pinned { memories[idx].importance = max(memories[idx].importance, 0.95) }
        persist()
    }

    func updateMemory(id: UUID, content: String, tags: [String]) {
        guard prepareForMutation() else { return }
        guard let cleaned = Self.cleanedContent(content),
              let idx = memories.firstIndex(where: { $0.id == id })
        else { return }
        automaticWriteGate.invalidate()
        let contentChanged = memories[idx].content != cleaned
        memories[idx].content = cleaned
        memories[idx].tags = Self.normalizedTags(tags)
        memories[idx].source = "manual-edit"
        memories[idx].confidence = max(memories[idx].confidence, 0.9)
        memories[idx].importance = max(memories[idx].importance, 0.9)
        memories[idx].updatedAt = .now
        memories[idx].lastSeenAt = .now
        memories[idx].lastDecayedAt = nil
        if contentChanged {
            memories[idx].embedding = nil          // içerik değişti → embedding bayat, yeniden hesaplanacak
            memories[idx].embeddingModel = nil
        }
        rebuildSearchIndex()
        persist()
    }

    @discardableResult
    func addManualMemory(content: String, tags: [String], pinned: Bool = true) -> AgentMemory? {
        guard let cleaned = Self.cleanedContent(content) else { return nil }
        guard prepareForMutation() else { return nil }
        return remember(
            content: cleaned,
            tags: Self.normalizedTags(tags),
            source: "manual",
            confidence: 0.98,
            importance: 0.98,
            pinned: pinned
        )
    }

    /// Heuristik fallback — yalnızca LLM memory-manager (MemoryManager) ulaşılamazsa
    /// devreye girer ve SADECE kullanıcının açıkça "bunu hatırla / unutma" dediği bilgiyi
    /// yakalar. Eski templated çıkarım (kalitesiz raw-text dökümü) kaldırıldı: LLM yoksa
    /// gürültü yazmaktansa hiç yazmamayı tercih eder.
    @discardableResult
    func absorbConversation(
        userText: String,
        assistantText: String,
        expectedAutomaticWriteGeneration: UInt64
    ) -> Int {
        guard automaticWriteGate.permits(expectedAutomaticWriteGeneration),
              prepareForMutation(),
              automaticWriteGate.permits(expectedAutomaticWriteGeneration),
              absorbConversationWithoutPersist(userText: userText, assistantText: assistantText)
        else { return 0 }
        rebuildSearchIndex()
        persist(expectedAutomaticWriteGeneration: expectedAutomaticWriteGeneration)
        return 1
    }

    /// Geçmiş sohbet migration'ı için tüm açık-hafıza adaylarını tek snapshot'ta
    /// yazar ve ancak o snapshot şifreli dosyada doğrulandıktan sonra başarı döner.
    /// Böylece ChatStore backfill imzasını bir crash/write failure öncesinde işaretlemez.
    func absorbConversationsDurably(
        _ pairs: [(userText: String, assistantText: String)],
        expectedAutomaticWriteGeneration: UInt64
    ) async -> Bool {
        // Cancellation yalnız mutation başlamadan yetkiyi düşürür. Mutation/persist
        // başladıktan sonra caller iptal olsa bile durable acknowledgement tamamlanır;
        // aksi halde ChatStore ledger ilerlemez ve eski tur ileride replay olur.
        guard AutomaticMemoryBulkPolicy.mayBegin(
                  isCancelled: Task.isCancelled,
                  generationMatches: automaticWriteGate.permits(
                      expectedAutomaticWriteGeneration
                  )
              ),
              !pairs.isEmpty,
              prepareForMutation(),
              automaticWriteGate.permits(expectedAutomaticWriteGeneration)
        else {
            return pairs.isEmpty
                && !Task.isCancelled
                && automaticWriteGate.permits(expectedAutomaticWriteGeneration)
                && storageState == .ready
        }

        let rollbackSnapshot = memories
        var changed = false
        for pair in pairs {
            changed = absorbConversationWithoutPersist(
                userText: pair.userText,
                assistantText: pair.assistantText
            ) || changed
        }
        guard changed else { return storageState == .ready }

        guard automaticWriteGate.permits(expectedAutomaticWriteGeneration) else {
            memories = rollbackSnapshot
            rebuildSearchIndex()
            return false
        }
        rebuildSearchIndex()
        guard automaticWriteGate.permits(expectedAutomaticWriteGeneration) else {
            memories = rollbackSnapshot
            rebuildSearchIndex()
            return false
        }
        persist(expectedAutomaticWriteGeneration: expectedAutomaticWriteGeneration)
        return await waitForDurablePersistence(ignoreCancellation: true)
    }

    private func absorbConversationWithoutPersist(
        userText: String,
        assistantText: String
    ) -> Bool {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let explicit = Self.explicitMemoryCandidate(from: trimmed)
        else { return false }
        _ = upsertMemory(
            content: explicit.content,
            tags: explicit.tags,
            source: "explicit",
            confidence: 0.96,
            importance: 0.98,
            pinned: true
        )
        return true
    }

    @discardableResult
    func remember(
        content: String,
        tags: [String],
        source: String,
        confidence: Double,
        importance: Double? = nil,
        type: MemoryType = .other,
        expiresAt: Date? = nil,
        pinned: Bool = false
    ) -> AgentMemory? {
        guard prepareForMutation() else { return nil }
        if Self.isUserManagedSource(source) {
            automaticWriteGate.invalidate()
        }
        let memory = upsertMemory(
            content: content,
            tags: tags,
            source: source,
            confidence: confidence,
            importance: importance,
            type: type,
            expiresAt: expiresAt,
            pinned: pinned
        )
        rebuildSearchIndex()
        persist()
        return memory
    }

    private func upsertMemory(
        content: String,
        tags: [String],
        source: String,
        confidence: Double,
        importance: Double? = nil,
        type: MemoryType = .other,
        expiresAt: Date? = nil,
        pinned: Bool = false
    ) -> AgentMemory {
        guard let cleanContent = Self.cleanedContent(content) else {
            preconditionFailure("Memory content must contain at least three visible characters")
        }
        let normalizedContent = Self.normalizedMemoryKey(cleanContent)
        let normalizedTags = Self.normalizedTags(tags)
        let safeConfidence = Self.bounded(confidence, default: 0.7, minimum: 0.0)
        let safeImportance = Self.bounded(
            importance,
            default: AgentMemory.defaultImportance(for: type),
            minimum: 0.0
        )

        if !normalizedContent.isEmpty,
           let existingID = memoryKeyToID[normalizedContent],
           let idx = memories.firstIndex(where: { $0.id == existingID }) {
            memories[idx].tags = Self.normalizedTags(memories[idx].tags + normalizedTags)
            if !Self.isUserManagedSource(memories[idx].source) || Self.isUserManagedSource(source) {
                memories[idx].source = source
            }
            memories[idx].confidence = max(memories[idx].confidence, safeConfidence)
            memories[idx].importance = max(memories[idx].importance, safeImportance)
            if memories[idx].type == .other, type != .other {
                memories[idx].type = type
            }
            memories[idx].updatedAt = .now
            memories[idx].lastSeenAt = .now
            memories[idx].lastDecayedAt = nil
            memories[idx].pinned = memories[idx].pinned || pinned
            // Aynı içerik tekrar doğrulandı — daha önce invalidate edildiyse geri getir.
            memories[idx].invalidatedAt = nil
            memories[idx].supersededBy = nil
            if pinned || expiresAt == nil {
                memories[idx].expiresAt = nil
            } else if memories[idx].expiresAt == nil {
                memories[idx].expiresAt = expiresAt
            }
            return memories[idx]
        }

        let memory = AgentMemory(
            content: cleanContent,
            tags: normalizedTags,
            source: source,
            confidence: safeConfidence,
            importance: safeImportance,
            type: type,
            expiresAt: expiresAt,
            pinned: pinned
        )
        memories.append(memory)
        // Aynı batch içindeki sonraki upsert'ler bu kaydı görebilsin
        // (tam indeks rebuild'i batch sonunda zaten çalışır).
        if !normalizedContent.isEmpty {
            memoryKeyToID[normalizedContent] = memory.id
        }
        return memory
    }

    /// Chat fallback'inin açık "hatırla" adayını üretir. Manual Memory ekranı bu
    /// yolu kullanmaz; kullanıcı orada kendi açık kararıyla istediği metni saklayabilir.
    static func explicitMemoryCandidate(
        from text: String
    ) -> (content: String, tags: [String])? {
        let words = Self.fold(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // Türkçe olumsuz çekimler affirmative kökü substring olarak içerir
        // (`hatırlama`, `hatırlamamanı`). Önce bunları ve açık vazgeçme
        // işaretlerini kapat; “unutma” ise olumlu bir hatırlatma komutudur.
        let negativeVerbPrefixes = [
            "hatirlama", "ekleme", "saklama", "kaydetme", "yazma", "girme", "tutma"
        ]
        let hasNegativeVerb = words.contains { word in
            negativeVerbPrefixes.contains { prefix in
                guard word.hasPrefix(prefix) else { return false }
                // Mastar `hatırlamak/eklemek` kendi başına olumsuz değildir; fakat
                // aşağıdaki affirmative whole-token kalıplarını da karşılamaz.
                return word.dropFirst(prefix.count).first != "k"
            }
        }
        let negativeMarkers: Set<String> = [
            "istemiyorum", "istemem", "isteme", "hayir", "sakin",
            "vazgectim", "vazgec", "demiyorum", "degil", "dont"
        ]
        let hasNegativeMarker = words.contains { word in
            negativeMarkers.contains(word)
                || negativeMarkers.contains { marker in
                    marker.count >= 5 && word.hasPrefix(marker)
                }
        } || Self.containsWordPhrase(["do", "not"], in: words)
        guard !hasNegativeVerb, !hasNegativeMarker else { return nil }

        // Substring değil whole-token phrase: `hatırlamamanı` artık `hatırla`
        // komutu sayılamaz. Noktalama ise token sınırı olarak doğal biçimde tolere edilir.
        let affirmativePhrases = [
            ["bunu", "hatirla"], ["sunu", "hatirla"], ["beni", "hatirla"],
            ["bunu", "unutma"], ["sunu", "unutma"],
            ["aklinda", "tut"],
            ["memoryye", "ekle"], ["memory", "e", "ekle"],
            ["hafizaya", "ekle"], ["hafizana", "ekle"],
            ["remember", "this"]
        ]
        guard affirmativePhrases.contains(where: {
            Self.containsWordPhrase($0, in: words)
        }) else { return nil }

        var cleaned = text
        let boundedCommandPatterns = [
            #"\bbunu[\p{P}\s]+hat[ıi]rla\b"#,
            #"\b[şs]unu[\p{P}\s]+hat[ıi]rla\b"#,
            #"\bbeni[\p{P}\s]+hat[ıi]rla\b"#,
            #"\bbunu[\p{P}\s]+unutma\b"#,
            #"\b[şs]unu[\p{P}\s]+unutma\b"#,
            #"\bakl[ıi]nda[\p{P}\s]+tut\b"#,
            #"\bmemoryye[\p{P}\s]+ekle\b"#,
            #"\bmemory[\p{P}\s]+e[\p{P}\s]+ekle\b"#,
            #"\bhaf[ıi]zaya[\p{P}\s]+ekle\b"#,
            #"\bhaf[ıi]zana[\p{P}\s]+ekle\b"#,
            #"\bremember[\p{P}\s]+this\b"#
        ]
        for pattern in boundedCommandPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive, .diacriticInsensitive]
            )
        }
        cleaned = cleaned
            .replacingOccurrences(of: "bunu hatırla", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "şunu hatırla", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "beni hatırla", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "bunu unutma", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "şunu unutma", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "aklında tut", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "memoryye ekle", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "memory'e ekle", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "hafızaya ekle", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "hafızana ekle", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "remember this", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-\n\t"))

        let content = cleaned.isEmpty ? text : cleaned
        guard let safeContent = Self.cleanedContent(content) else { return nil }
        guard !Self.shouldRejectAutomaticMemory(safeContent) else { return nil }
        return (safeContent, Self.tags(for: safeContent))
    }

    private nonisolated static func containsWordPhrase(
        _ phrase: [String],
        in words: [String]
    ) -> Bool {
        guard !phrase.isEmpty, phrase.count <= words.count else { return false }
        for start in 0...(words.count - phrase.count) {
            if Array(words[start..<(start + phrase.count)]) == phrase {
                return true
            }
        }
        return false
    }

    private func touch(_ selected: [AgentMemory]) {
        guard !selected.isEmpty else { return }
        let ids = Set(selected.map(\.id))
        let now = Date()
        for idx in memories.indices where ids.contains(memories[idx].id) {
            memories[idx].lastAccessedAt = now
        }
        // Retrieval bir truth sinyali değildir ve her sorguda bütün embedding payload'ını
        // diske yazmak pahalıdır. Access zamanı yalnız bu süreçte tanısal tutulur.
    }

    private static func makeMemoryURLs() -> (encrypted: URL, legacy: URL) {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base.appendingPathComponent("Hercules", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return (
            dir.appendingPathComponent("agent-memory.herculesbox"),
            dir.appendingPathComponent("agent-memory.json")
        )
    }

    private func refreshFromDiskIfChanged() {
        guard !deferredWriteInFlight, storageState == .ready else { return }
        let fingerprint = Self.diskFingerprint(for: memoryURL)
        guard fingerprint != loadedFingerprint else { return }
        automaticWriteGate.invalidate()
        load()
        if storageState.allowsMutation, pruneExpiredMemories() {
            persist()
        }
    }

    /// Her RAM mutasyonundan hemen önce external disk değişikliğini birleştirir;
    /// load conflict/lock tespit ederse çağıran eski `ready` varsayımıyla devam etmez.
    private func prepareForMutation() -> Bool {
        refreshFromDiskIfChanged()
        return storageState.allowsMutation
    }

    private func load() {
        let fingerprint = Self.diskFingerprint(for: memoryURL)
        let fm = FileManager.default
        let encryptedExists = fm.fileExists(atPath: memoryURL.path)
        let legacyExists = fm.fileExists(atPath: legacyMemoryURL.path)
        if legacyExists {
            // Şifreleme async tamamlanana (veya bir conflict çözülene) kadar legacy
            // dosya en azından yalnız kullanıcı tarafından okunabilir ve backup dışıdır.
            HerculesMemoryVault.harden(legacyMemoryURL)
        }

        guard encryptedExists || legacyExists else {
            memories = []
            storageState = .ready
            pendingLegacyCleanup = false
            loadedFingerprint = fingerprint
            rebuildSearchIndex()
            return
        }

        if encryptedExists {
            do {
                let envelope = try Data(contentsOf: memoryURL)
                let plaintext = try HerculesMemoryVault.open(envelope, aad: Self.memoryAAD)
                let encryptedPayload = try Self.decodePayload(plaintext)
                let encryptedMemories = Self.deduplicated(encryptedPayload.memories)
                // Primary ciphertext doğrulandı. Bundan sonra eski plaintext'in
                // okunamaması geçerli hafızayı görünmez yapmamalı.
                memories = encryptedMemories
                var cleanupWarning: String?

                if legacyExists {
                    do {
                        let legacyData = try Data(contentsOf: legacyMemoryURL)
                        let legacyPayload = try Self.decodePayload(legacyData)
                        let legacyMemories = Self.deduplicated(legacyPayload.memories)
                        guard legacyMemories == encryptedMemories else {
                            storageState = .conflict(
                                "Şifreli ve eski düz-metin hafıza farklı. Veri kaybını önlemek için yazma kilitlendi."
                            )
                            loadedFingerprint = fingerprint
                            HerculesMemoryVault.harden(memoryURL)
                            rebuildSearchIndex()
                            postLocalMemoryChanged()
                            return
                        }
                        // Ciphertext açıldı + payload birebir eşleşti; eski plaintext
                        // artık güvenle kaldırılabilir.
                        try fm.removeItem(at: legacyMemoryURL)
                    } catch {
                        storageState = .conflict(
                            "Şifreli hafıza doğrulandı fakat eski düz-metin dosya okunamadı veya kaldırılamadı. "
                                + "Geçerli şifreli kopya gösteriliyor; veri kaybını önlemek için yazma kilitlendi. "
                                + error.localizedDescription
                        )
                        loadedFingerprint = fingerprint
                        HerculesMemoryVault.harden(memoryURL)
                        rebuildSearchIndex()
                        postLocalMemoryChanged()
                        return
                    }
                }

                do {
                    try HerculesMemoryVault.quarantineLegacyMemoryBackups(
                        in: memoryURL.deletingLastPathComponent()
                    )
                } catch {
                    cleanupWarning =
                        "Şifreli hafıza doğrulandı fakat eski düz-metin kurtarma kopyaları "
                        + "şifreli karantinaya taşınamadı: \(error.localizedDescription)"
                }
                storageState = cleanupWarning.map(LocalMemoryStorageState.writeFailed) ?? .ready
                if cleanupWarning == nil { pendingLegacyCleanup = false }
                loadedFingerprint = fingerprint
                HerculesMemoryVault.harden(memoryURL)
            } catch let error as HerculesMemoryVault.VaultError {
                storageState = Self.storageState(for: error)
                loadedFingerprint = fingerprint
                // Son iyi RAM snapshot'ını koru; decrypt/key hatasını "0 kayıt" sayma.
            } catch {
                storageState = .corrupt(
                    "Hafıza dosyası okunamadı; mevcut dosyanın üstüne yazılmadı. \(error.localizedDescription)"
                )
                loadedFingerprint = fingerprint
            }
            rebuildSearchIndex()
            postLocalMemoryChanged()
            return
        }

        // Transactional plaintext migration: strict decode → RAM'e al → encrypted
        // atomic write+decrypt verify → yalnız writer success callback'inde plaintext sil.
        do {
            let legacyData = try Data(contentsOf: legacyMemoryURL)
            let payload = try Self.decodePayload(legacyData)
            memories = Self.deduplicated(payload.memories)
            storageState = .ready
            pendingLegacyCleanup = true
            loadedFingerprint = fingerprint
            rebuildSearchIndex()
            persist()
        } catch {
            storageState = .corrupt(
                "Eski hafıza dosyası çözümlenemedi; korunuyor ve üstüne yazılmıyor. \(error.localizedDescription)"
            )
            loadedFingerprint = fingerprint
            rebuildSearchIndex()
            postLocalMemoryChanged()
        }
    }

    private static func decodePayload(_ data: Data) throws -> MemoryPayload {
        let payload: MemoryPayload
        do {
            payload = try decoder.decode(MemoryPayload.self, from: data)
        } catch {
            payload = try preciseDateDecoder.decode(MemoryPayload.self, from: data)
        }
        guard (1...2).contains(payload.version) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return payload
    }

    private static func storageState(for error: HerculesMemoryVault.VaultError) -> LocalMemoryStorageState {
        switch error {
        case .keyUnavailable, .keyMissingForExistingVault, .keyConflict, .invalidKey:
            return .locked(error.localizedDescription)
        case .invalidEnvelope, .authenticationFailed:
            return .corrupt(
                "\(error.localizedDescription) Dosyanın üstüne yazılmadı."
            )
        }
    }

    @discardableResult
    private func pruneExpiredMemories() -> Bool {
        let now = Date()
        var changed = false
        for index in memories.indices {
            if LocalMemoryInvalidationPolicy.softInvalidateIfExpired(
                &memories[index],
                now: now
            ) {
                changed = true
            }
        }
        if changed {
            rebuildSearchIndex()
        }
        return changed
    }

    /// Diske yazımı arka plana (writer actor) devreder — encode + I/O main thread'i bloklamaz.
    private func persist(
        expectedAutomaticWriteGeneration: UInt64? = nil,
        forceKeyCreation: Bool = false
    ) {
        guard storageState.allowsMutation else { return }
        let payload = memories.isEmpty ? nil : MemoryPayload(version: 2, savedAt: .now, memories: memories)
        writeSequence += 1
        let sequence = writeSequence
        let generation = writeGate.currentGeneration()
        let url = memoryURL
        let writer = fileWriter
        let gate = writeGate
        let automaticGate = automaticWriteGate
        deferredWriteInFlight = true
        // Task @MainActor context'ini miras alır: actor write off-main, devamı tekrar main'de.
        let task = Task<MemoryWriteResult, Never> { @MainActor [weak self] in
            let result = await writer.write(
                payload: payload,
                to: url,
                sequence: sequence,
                generation: generation,
                gate: gate,
                automaticGeneration: expectedAutomaticWriteGeneration,
                automaticGate: automaticGate,
                forceKeyCreation: forceKeyCreation
            )
            guard let self, self.writeSequence == sequence else { return result }
            self.completedWriteSequence = sequence
            self.completedWriteSucceeded = result.succeeded
            if result.succeeded {
                self.loadedFingerprint = Self.diskFingerprint(for: self.memoryURL)
                self.storageState = .ready
                if self.pendingLegacyCleanup {
                    do {
                        if FileManager.default.fileExists(atPath: self.legacyMemoryURL.path) {
                            try FileManager.default.removeItem(at: self.legacyMemoryURL)
                            try Self.synchronizeDirectory(
                                self.legacyMemoryURL.deletingLastPathComponent()
                            )
                        }
                        self.pendingLegacyCleanup = false
                    } catch {
                        self.storageState = .writeFailed(
                            "Hafıza şifrelendi ama eski düz-metin dosya kaldırılamadı: \(error.localizedDescription)"
                        )
                    }
                }
            } else if let message = result.message {
                self.storageState = .writeFailed(
                    "Hafıza diske güvenli biçimde yazılamadı; RAM kopyası korunuyor. \(message)"
                )
            }
            self.deferredWriteInFlight = false
            if self.latestWriteTaskSequence == sequence {
                self.latestWriteTask = nil
                self.latestWriteTaskSequence = nil
            }
            self.postLocalMemoryChanged()
            return result
        }
        latestWriteTask = task
        latestWriteTaskSequence = sequence
        postLocalMemoryChanged()
    }

    /// O anki canonical RAM snapshot'ının doğrulanmış disk commit'ini bekler.
    /// Aynı nesildeki daha yeni bir persist varsa onu takip eder; reload nesli
    /// değiştirirse eski RAM snapshot'ı artık kanıtlanamayacağı için `false` döner.
    private func waitForDurablePersistence(ignoreCancellation: Bool = false) async -> Bool {
        let requiredGeneration = writeGate.currentGeneration()
        guard var task = latestWriteTask,
              var sequence = latestWriteTaskSequence
        else {
            return storageState == .ready
        }

        while true {
            let result = await task.value
            guard AutomaticMemoryBulkPolicy.mayContinueDurableWait(
                isCancelled: Task.isCancelled,
                ignoreCancellation: ignoreCancellation,
                writeGenerationMatches: writeGate.currentGeneration() == requiredGeneration
            )
            else { return false }

            if writeSequence == sequence {
                return result.succeeded
            }
            if completedWriteSequence == writeSequence {
                return completedWriteSucceeded
            }
            guard let nextTask = latestWriteTask,
                  let nextSequence = latestWriteTaskSequence
            else { return false }
            task = nextTask
            sequence = nextSequence
        }
    }

    private func postLocalMemoryChanged() {
        NotificationCenter.default.post(name: .localMemoryChanged, object: nil)
    }

    private func cancelDeferredWrite() {
        writeSequence += 1          // uçuştaki yazımların fingerprint güncellemesini geçersiz kıl
        // Aktif commit varsa bitmesini bekle; sonra generation'ı senkron değiştir.
        // Bu dönüşten itibaren eski nesil writer diske dokunamaz ve `load()` güvenlidir.
        writeGate.invalidate()
        deferredWriteInFlight = false
        latestWriteTask = nil
        latestWriteTaskSequence = nil
        // Writer actor'ı da yetkilendir: barrier'a kadar olan (stale) yazımlar diske vurmadan reddedilsin.
        // Sıradaki gerçek persist > barrier sequence kullanacağı için meşru yazımlar etkilenmez.
        let barrier = writeSequence
        let writer = fileWriter
        Task { await writer.invalidate(upTo: barrier) }
    }

    private func rebuildSearchIndex() {
        // uniquingKeysWith: `uniqueKeysWithValues` yinelenen id/key'de runtime trap'ti —
        // decode yolunda id benzersizliği garanti edilmediği için crash-loop riskiydi.
        memoryTermsByID = Dictionary(memories.map { memory in
            (memory.id, Set(Self.tokens(memory.content + " " + memory.tags.joined(separator: " "))))
        }, uniquingKeysWith: { _, last in last })
        memoryTagTermsByID = Dictionary(memories.map { memory in
            (memory.id, Set(memory.tags.flatMap(Self.tokens)))
        }, uniquingKeysWith: { _, last in last })
        memoryKeyToID = Dictionary(memories.map { memory in
            (Self.normalizedMemoryKey(memory.content), memory.id)
        }, uniquingKeysWith: { first, _ in first })
    }

    private nonisolated static func captureRawFile(_ url: URL) throws -> Data? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size >= 0,
              size <= HerculesMemoryArchive.maximumArchiveBytes
        else {
            throw LocalMemoryRestoreError.persistenceFailed(
                "Eski hafıza dosyası güvenli biçimde yedeklenemedi."
            )
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private nonisolated static func restoreRawFile(_ data: Data?, to url: URL) throws {
        let fileManager = FileManager.default
        if let data {
            try data.write(to: url, options: [.atomic])
            HerculesMemoryVault.harden(url)
            try synchronizeFileAndDirectory(url)
            guard try Data(contentsOf: url, options: [.mappedIfSafe]) == data else {
                throw LocalMemoryRestoreError.rollbackFailed(
                    "Eski dosyanın geri yazım doğrulaması eşleşmedi."
                )
            }
        } else if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            try synchronizeDirectory(url.deletingLastPathComponent())
        }
    }

    private static func rollbackMemories(
        encrypted: Data?,
        legacy: Data?,
        storageState: LocalMemoryStorageState,
        fallback: [AgentMemory]
    ) throws -> [AgentMemory] {
        switch storageState {
        case .ready, .writeFailed:
            break
        case .locked, .corrupt, .conflict:
            // Locked/corrupt/conflict state intentionally preserves the last known
            // RAM view even when its opaque disk artifact cannot be decoded.
            return fallback
        }
        if let encrypted {
            let plaintext = try HerculesMemoryVault.open(encrypted, aad: memoryAAD)
            return deduplicated(try decodePayload(plaintext).memories)
        }
        if let legacy {
            return deduplicated(try decodePayload(legacy).memories)
        }
        return []
    }

    private static func persistedSnapshot(
        _ expected: [AgentMemory],
        matches url: URL
    ) -> Bool {
        if expected.isEmpty {
            return !FileManager.default.fileExists(atPath: url.path)
        }
        do {
            let envelope = try Data(contentsOf: url, options: [.mappedIfSafe])
            let plaintext = try HerculesMemoryVault.open(envelope, aad: memoryAAD)
            let payload = try decodePayload(plaintext)
            return payload.version == 2 && payload.memories == expected
        } catch {
            return false
        }
    }

    private nonisolated static func synchronizeFileAndDirectory(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try synchronizeDirectory(url.deletingLastPathComponent())
    }

    private nonisolated static func synchronizeDirectory(_ directory: URL) throws {
        #if canImport(Darwin)
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        #endif
    }

    private static func diskFingerprint(for url: URL) -> DiskFingerprint {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DiskFingerprint(exists: false, modificationDate: nil, fileSize: nil)
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return DiskFingerprint(
            exists: true,
            modificationDate: values?.contentModificationDate,
            fileSize: values?.fileSize
        )
    }

    private static func isExpired(_ memory: AgentMemory, now: Date) -> Bool {
        guard !memory.pinned, let expiresAt = memory.expiresAt else { return false }
        return expiresAt < now
    }

    private static func tags(for text: String) -> [String] {
        let lower = fold(text)
        var tags: Set<String> = []
        if containsAny(lower, needles: [
            "protein", "kalori", "makro", "yemek", "ogun", "öğün", "pismis",
            "pişmiş", "cig", "çiğ", "whey", "protein tozu", "pirinc", "pirinç",
            "tavuk", "yumurta", "karbonhidrat"
        ]) {
            tags.insert("nutrition")
        }
        if containsAny(lower, needles: [
            "antrenman", "idman", "workout", "gym", "hipertrofi", "hypertrophy",
            "bodybuilding", "program", "hareket", "rir", "set", "bench", "squat",
            "deadlift", "upper", "lower", "calf", "hamstring", "quad"
        ]) {
            tags.insert("training")
        }
        if containsAny(lower, needles: ["whey", "protein tozu", "kreatin", "creatine", "bcaa", "ssn", "gentopure", "protein ocean"]) {
            tags.insert("supplement")
        }
        if containsAny(lower, needles: ["chat", "memory", "hafiza", "hafıza", "sidebar", "layout", "preset", "takvim", "profil", "icloud", "shortcut"]) {
            tags.insert("app")
        }
        if containsAny(lower, needles: ["sidebar", "layout", "responsive", "tasarim", "tasarım", "renk", "popup", "pop-up", "buton", "arrow", "resize", "scroll"]) {
            tags.insert("ui")
        }
        if containsAny(lower, needles: ["bulk", "cut", "definasyon", "kilo", "yag", "yağ", "hedef"]) {
            tags.insert("goal")
        }
        if containsAny(lower, needles: ["seviyorum", "sevmiyorum", "tercih", "istemiyorum", "istemiyoruz", "olmasin", "olmasın"]) {
            tags.insert("preference")
        }
        if containsAny(lower, needles: ["ucuz", "butce", "bütçe", "ulasılabilir", "ulaşılabilir"]) {
            tags.insert("budget")
        }
        return Array(tags).sorted()
    }

    private static func tokens(_ text: String) -> [String] {
        let shortDomainTokens: Set<String> = [
            "kg", "g", "gr", "mg", "ml", "l", "cm", "mm", "lb", "oz",
            "rm", "rir", "rpe", "ui", "ux", "ai"
        ]
        return fold(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count >= 3
                    || token.allSatisfy(\.isNumber)
                    || shortDomainTokens.contains(token)
            }
    }

    private static func fold(_ text: String) -> String {
        text
            .lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
    }

    static func normalizedMemoryKey(_ text: String) -> String {
        tokens(text).joined(separator: " ")
    }

    private static func cleanedContent(_ value: String?) -> String? {
        let scalars = (value ?? "").unicodeScalars.map { scalar -> Character in
            Character(CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar))
        }
        let collapsed = String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count >= 3 else { return nil }
        return String(collapsed.prefix(1_200))
    }

    /// AI/sohbet hafızası parola kasası değildir. Model cevabı şema-valid ve kullanıcı
    /// alıntısına grounded olsa bile credential'ı kalıcı hafızaya taşıyamaz: hafıza
    /// sonraki turlarda üçüncü taraf modele enjekte edildiği için bu kontrol prompt
    /// kuralı değil, host-side sink policy'sidir.
    ///
    /// Manual Memory ekranı yazım anında bilinçli olarak bu politikadan geçmez; kayıt
    /// yerelde kalabilir. Aynı matcher provider çıkışında yeniden kullanılır ve böyle
    /// bir manuel/legacy kayıt hiçbir modele gönderilmez.
    /// Credential türünün kendisini söyleyen bir memory de gereksiz risk taşır.
    /// Tam değeri yakalamaya bel bağlamadan fail-closed davran.
    nonisolated private static let credentialMarkers = [
        "password", "passphrase", "parola", "sifre",
        "api key", "api_key", "apikey",
        "access token", "access_token", "refresh token", "auth token",
        "client secret", "client_secret",
        "private key", "private_key",
        "seed phrase", "recovery phrase", "mnemonic",
        "kurtarma kelime", "kurtarma cumle"
    ]

    /// Yaygın sağlayıcı token'ları, JWT/basic/bearer değerleri ve PEM anahtarları
    /// etiketsiz yapıştırılmış olsa bile engellenir. BİR kez derlenir:
    /// `String.range(of:options:.regularExpression)` her çağrıda NSRegularExpression
    /// kuruyordu — corpus × 8 pattern × mesaj başına 3-4 geçişte binlerce derleme.
    nonisolated private static let secretRegexes: [NSRegularExpression] = [
        #"-----begin [a-z0-9 ]*(?:private key|secret key)-----"#,
        #"\bsk-(?:proj-)?[a-z0-9_-]{12,}\b"#,
        #"\bgithub_pat_[a-z0-9_]{12,}\b"#,
        #"\bgh[pousr]_[a-z0-9]{12,}\b"#,
        #"\bAKIA[A-Z0-9]{16}\b"#,
        #"\bxox[baprs]-[a-z0-9-]{10,}\b"#,
        #"\b(?:bearer|basic)\s+[a-z0-9._~+/\-=]{8,}\b"#,
        #"\beyJ[a-z0-9_-]{8,}\.[a-z0-9_-]{8,}\.[a-z0-9_-]{8,}\b"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    nonisolated static func shouldRejectAutomaticMemory(_ text: String) -> Bool {
        let folded = text
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "tr_TR")
            )
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")

        if Self.credentialMarkers.contains(where: folded.contains) {
            return true
        }

        let range = NSRange(text.startIndex..., in: text)
        return Self.secretRegexes.contains { regex in
            regex.firstMatch(in: text, range: range) != nil
        }
    }

    /// Model-güvenlik kararı memory başına cache'lenir: karar yalnız içerik+etikete
    /// bağlı, corpus her mesajda 3-4 kez filtrelendiği için aynı kaydı tekrar
    /// tekrar taramak saf israftı. `updatedAt` değişince yeniden hesaplanır.
    private final class ModelSafetyCache: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [UUID: (stamp: Date, safe: Bool)] = [:]

        func isSafe(_ memory: AgentMemory, compute: (AgentMemory) -> Bool) -> Bool {
            lock.lock()
            if let hit = values[memory.id], hit.stamp == memory.updatedAt {
                lock.unlock()
                return hit.safe
            }
            lock.unlock()
            let result = compute(memory)
            lock.lock()
            // Kaba sınır: corpus'un çok üstünde büyürse sıfırla (silinen id'ler birikmesin).
            if values.count > 4_096 { values.removeAll(keepingCapacity: true) }
            values[memory.id] = (memory.updatedAt, result)
            lock.unlock()
            return result
        }
    }

    nonisolated private static let modelSafetyCache = ModelSafetyCache()

    /// Provider/model sınırındaki son savunma. Manuel veya eski bir kayıt yerel
    /// depodan silinmez ve Memory ekranında düzenlenebilir; yalnız içerik ya da
    /// etiketleri credential işaretliyorsa hiçbir model bağlamına çıkarılmaz.
    ///
    /// Filtre ayrı bir secret tanımı tutmaz: otomatik yazma kapısındaki aynı
    /// host-side matcher tek doğruluk kaynağıdır.
    nonisolated static func isSafeForModelContext(_ memory: AgentMemory) -> Bool {
        modelSafetyCache.isSafe(memory) { m in
            !shouldRejectAutomaticMemory(
                ([m.content] + m.tags).joined(separator: "\n")
            )
        }
    }

    nonisolated static func modelSafeMemories(_ values: [AgentMemory]) -> [AgentMemory] {
        values.filter(isSafeForModelContext)
    }

    /// Otomatik (LLM/chat/assistant) kaynaklı — decay'e tabi olanlar. Manuel/explicit hariç.
    private static func isAutoSource(_ source: String) -> Bool {
        source.hasPrefix("llm") || source.hasPrefix("chat") || source.hasPrefix("assistant")
    }

    private static func isUserManagedSource(_ source: String) -> Bool {
        source == "manual" || source == "manual-edit" || source == "explicit"
    }

    private static func bounded(
        _ value: Double?,
        default fallback: Double,
        minimum: Double
    ) -> Double {
        guard let value, value.isFinite else { return min(1.0, max(minimum, fallback)) }
        return min(1.0, max(minimum, value))
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.flatMap { tag in
            tag
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
                .map {
                    String(Self.fold(String($0)).prefix(40))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
        })).sorted().prefix(12).map { $0 }
    }

    private static func containsAny(_ text: String, needles: [String]) -> Bool {
        let haystack = fold(text)
        return needles.map { fold($0) }.contains { haystack.contains($0) }
    }

    private static func deduplicated(_ loaded: [AgentMemory]) -> [AgentMemory] {
        var output: [AgentMemory] = []
        var indexByKey: [String: Int] = [:]   // normalize anahtarı → output indeksi (O(n) dedupe)
        for memory in loaded {
            let key = normalizedMemoryKey(memory.content)
            guard !key.isEmpty else {
                output.append(memory)
                continue
            }
            if let idx = indexByKey[key] {
                output[idx].tags = normalizedTags(output[idx].tags + memory.tags)
                output[idx].confidence = max(output[idx].confidence, memory.confidence)
                output[idx].importance = max(output[idx].importance, memory.importance)
                output[idx].pinned = output[idx].pinned || memory.pinned
                if !isUserManagedSource(output[idx].source) || isUserManagedSource(memory.source) {
                    output[idx].source = memory.source
                }
                if output[idx].type == .other, memory.type != .other {
                    output[idx].type = memory.type
                }
                output[idx].createdAt = min(output[idx].createdAt, memory.createdAt)
                output[idx].updatedAt = max(output[idx].updatedAt, memory.updatedAt)
                output[idx].lastSeenAt = max(output[idx].lastSeenAt, memory.lastSeenAt)
                output[idx].lastAccessedAt = latest(output[idx].lastAccessedAt, memory.lastAccessedAt)
                output[idx].lastDecayedAt = latest(output[idx].lastDecayedAt, memory.lastDecayedAt)
                if memory.updatedAt >= output[idx].updatedAt,
                   memory.embeddingModel != nil,
                   memory.embedding != nil {
                    output[idx].embedding = memory.embedding
                    output[idx].embeddingModel = memory.embeddingModel
                }
                // İkisinden biri aktifse aktif kabul et — aktif kayıt eskiyi supersede eder.
                if output[idx].invalidatedAt == nil || memory.invalidatedAt == nil {
                    output[idx].invalidatedAt = nil
                    output[idx].supersededBy = nil
                } else {
                    output[idx].invalidatedAt = max(output[idx].invalidatedAt!, memory.invalidatedAt!)
                }
                if output[idx].expiresAt == nil || memory.expiresAt == nil {
                    output[idx].expiresAt = nil
                } else {
                    output[idx].expiresAt = max(output[idx].expiresAt!, memory.expiresAt!)
                }
            } else {
                indexByKey[key] = output.count
                output.append(memory)
            }
        }
        return output
    }

    private static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil): return nil
        case (let value?, nil), (nil, let value?): return value
        case (let lhs?, let rhs?): return max(lhs, rhs)
        }
    }

}

extension Notification.Name {
    static let localMemoryChanged = Notification.Name("hercules.local-memory.changed")
    static let embeddingStatusChanged = Notification.Name("hercules.embedding-status.changed")
}

/// Embedding modelinin yükleme/backfill durumu — Memory ekranı bunu gösterir.
