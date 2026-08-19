import CryptoKit
import Foundation
import Security
#if canImport(Darwin)
import Darwin
#endif

/// User-controlled, passphrase-encrypted portable backup for the complete
/// HERCULES agent-memory history.
///
/// V1 envelope (UTF-8 JSON, sorted keys):
/// - `magic`: exactly `HERCULESMEMORY`
/// - `formatVersion`: exactly `1`
/// - `kdf`: exactly `PBKDF2-SHA256`
/// - `iterations`: `100_000...1_000_000`
/// - `salt`: canonical base64 for exactly 16 random bytes
/// - `ciphertext`: canonical base64 for CryptoKit's AES-GCM `combined` bytes
///
/// The encrypted plaintext is payload schema 1 and uses the fixed AAD
/// `hercules.portable-memory-archive:v1`. No API in this type writes plaintext
/// to disk.
enum HerculesMemoryArchive {
    static let fileExtension = "herculesmemory"
    static let magic = "HERCULESMEMORY"
    static let formatVersion = 1
    static let payloadSchemaVersion = 1
    static let kdfName = "PBKDF2-SHA256"
    static let archiveAAD = "hercules.portable-memory-archive:v1"
    static let defaultIterations = 200_000
    static let allowedIterations = 100_000...1_000_000

    static let maximumArchiveBytes = 80 * 1_024 * 1_024
    static let maximumPlaintextBytes = 64 * 1_024 * 1_024
    static let maximumRecordCount = 100_000

    enum ArchiveError: LocalizedError, Equatable {
        case emptyPassphrase
        case weakPassphrase
        case passphraseTooLong
        case invalidIterations
        case invalidFileExtension
        case archiveTooLarge
        case invalidEnvelope
        case unsupportedFormat
        case authenticationFailed
        case invalidPayload
        case duplicateRecordID
        case invalidRecord
        case persistenceFailed

        var errorDescription: String? {
            switch self {
            case .emptyPassphrase:
                return "Yedek parolası boş olamaz."
            case .weakPassphrase:
                return "Yedek parolası en az 8 karakter olmalı."
            case .passphraseTooLong:
                return "Yedek parolası çok uzun."
            case .invalidIterations:
                return "Yedek anahtar türetme ayarı güvenli aralığın dışında."
            case .invalidFileExtension:
                return "Yedek dosyası .herculesmemory uzantılı olmalı."
            case .archiveTooLarge:
                return "Hafıza yedeği izin verilen boyutu aşıyor."
            case .invalidEnvelope:
                return "Hafıza yedeği biçimi geçersiz."
            case .unsupportedFormat:
                return "Bu hafıza yedeği sürümü desteklenmiyor."
            case .authenticationFailed:
                return "Yedek parolası yanlış veya dosyanın bütünlüğü bozulmuş."
            case .invalidPayload:
                return "Yedekteki hafıza şeması geçersiz."
            case .duplicateRecordID:
                return "Yedekte yinelenen hafıza kimliği var."
            case .invalidRecord:
                return "Yedekte geçersiz bir hafıza kaydı var."
            case .persistenceFailed:
                return "Şifreli hafıza yedeği güvenli biçimde kaydedilemedi."
            }
        }
    }

    struct DecodedArchive: Sendable, Equatable {
        var exportedAt: Date
        var records: [AgentMemory]
    }

    private struct Envelope: Codable {
        var magic: String
        var formatVersion: Int
        var kdf: String
        var iterations: Int
        var salt: String
        var ciphertext: String
    }

    private struct Payload: Codable {
        var schemaVersion: Int
        var exportedAt: Date
        var records: [Record]
    }

    /// A synthesized Codable DTO is intentional. AgentMemory's legacy decoder
    /// repairs/clamps old on-device values; restore must instead reject malformed
    /// archive values before the provider mutates any state.
    private struct Record: Codable {
        var id: UUID
        var content: String
        var tags: [String]
        var source: String
        var confidence: Double
        var importance: Double
        var type: MemoryType
        var createdAt: Date
        var updatedAt: Date
        var lastSeenAt: Date
        var lastAccessedAt: Date?
        var lastDecayedAt: Date?
        var expiresAt: Date?
        var pinned: Bool
        var invalidatedAt: Date?
        var supersededBy: UUID?
        var embedding: String?
        var embeddingModel: String?

        init(_ memory: AgentMemory) {
            id = memory.id
            content = memory.content
            tags = memory.tags
            source = memory.source
            confidence = memory.confidence
            importance = memory.importance
            type = memory.type
            createdAt = memory.createdAt
            updatedAt = memory.updatedAt
            lastSeenAt = memory.lastSeenAt
            lastAccessedAt = memory.lastAccessedAt
            lastDecayedAt = memory.lastDecayedAt
            expiresAt = memory.expiresAt
            pinned = memory.pinned
            invalidatedAt = memory.invalidatedAt
            supersededBy = memory.supersededBy
            embedding = memory.embedding.map(AgentMemory.encodeEmbedding)
            embeddingModel = memory.embeddingModel
        }

        func memory() throws -> AgentMemory {
            let vector: [Float]?
            if let embedding {
                guard canonicalBase64(embedding),
                      let decoded = AgentMemory.decodeEmbedding(embedding),
                      decoded.count == EmbeddingService.dimension
                else { throw ArchiveError.invalidRecord }
                vector = decoded
            } else {
                vector = nil
            }

            guard (vector == nil) == (embeddingModel == nil) else {
                throw ArchiveError.invalidRecord
            }
            if let embeddingModel {
                guard validString(embeddingModel, minimum: 1, maximumUTF8Bytes: 1_024)
                else { throw ArchiveError.invalidRecord }
            }

            return AgentMemory(
                id: id,
                content: content,
                tags: tags,
                source: source,
                confidence: confidence,
                importance: importance,
                type: type,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastSeenAt: lastSeenAt,
                lastAccessedAt: lastAccessedAt,
                lastDecayedAt: lastDecayedAt,
                expiresAt: expiresAt,
                pinned: pinned,
                invalidatedAt: invalidatedAt,
                supersededBy: supersededBy,
                embedding: vector,
                embeddingModel: embeddingModel
            )
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static func seal(
        records: [AgentMemory],
        passphrase: String,
        iterations: Int = defaultIterations,
        exportedAt: Date = .now
    ) throws -> Data {
        try validatePassphrase(passphrase)
        guard allowedIterations.contains(iterations) else {
            throw ArchiveError.invalidIterations
        }
        try validate(records: records)
        guard exportedAt.timeIntervalSince1970.isFinite else {
            throw ArchiveError.invalidPayload
        }

        let payload = Payload(
            schemaVersion: payloadSchemaVersion,
            exportedAt: exportedAt,
            records: records.map(Record.init)
        )
        let plaintext = try encoder.encode(payload)
        guard plaintext.count <= maximumPlaintextBytes else {
            throw ArchiveError.archiveTooLarge
        }

        var salt = Data(count: 16)
        let randomStatus = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw ArchiveError.persistenceFailed
        }

        let key = try derivedKey(
            passphrase: passphrase,
            salt: salt,
            iterations: iterations
        )
        let box = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: Data(archiveAAD.utf8)
        )
        guard let combined = box.combined else {
            throw ArchiveError.invalidEnvelope
        }

        let envelope = Envelope(
            magic: magic,
            formatVersion: formatVersion,
            kdf: kdfName,
            iterations: iterations,
            salt: salt.base64EncodedString(),
            ciphertext: combined.base64EncodedString()
        )
        let archive = try encoder.encode(envelope)
        guard archive.count <= maximumArchiveBytes else {
            throw ArchiveError.archiveTooLarge
        }
        return archive
    }

    /// Fully authenticates and strictly validates the complete payload before
    /// returning records. Callers can therefore perform replace semantics only
    /// after this method succeeds.
    static func open(_ archive: Data, passphrase: String) throws -> DecodedArchive {
        try validatePassphrase(passphrase)
        guard !archive.isEmpty else { throw ArchiveError.invalidEnvelope }
        guard archive.count <= maximumArchiveBytes else {
            throw ArchiveError.archiveTooLarge
        }

        let envelope = try decodeAndValidateEnvelope(archive)
        // All cheap structural checks above deliberately happen before the KDF.
        let salt = Data(base64Encoded: envelope.salt)!
        let combined = Data(base64Encoded: envelope.ciphertext)!
        let key = try derivedKey(
            passphrase: passphrase,
            salt: salt,
            iterations: envelope.iterations
        )

        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            plaintext = try AES.GCM.open(
                box,
                using: key,
                authenticating: Data(archiveAAD.utf8)
            )
        } catch {
            throw ArchiveError.authenticationFailed
        }
        guard plaintext.count <= maximumPlaintextBytes else {
            throw ArchiveError.archiveTooLarge
        }

        try validatePayloadJSONSchema(plaintext)
        let payload: Payload
        do {
            payload = try decoder.decode(Payload.self, from: plaintext)
        } catch {
            throw ArchiveError.invalidPayload
        }
        guard payload.schemaVersion == payloadSchemaVersion,
              payload.exportedAt.timeIntervalSince1970.isFinite,
              payload.records.count <= maximumRecordCount
        else { throw ArchiveError.invalidPayload }

        let records = try payload.records.map { record -> AgentMemory in
            try validate(record: record)
            return try record.memory()
        }
        try validate(records: records)
        return DecodedArchive(exportedAt: payload.exportedAt, records: records)
    }

    static func write(
        records: [AgentMemory],
        passphrase: String,
        to url: URL,
        iterations: Int = defaultIterations,
        exportedAt: Date = .now
    ) throws {
        guard url.pathExtension.lowercased() == fileExtension else {
            throw ArchiveError.invalidFileExtension
        }
        let archive = try seal(
            records: records,
            passphrase: passphrase,
            iterations: iterations,
            exportedAt: exportedAt
        )
        try writeCiphertextDurably(archive, to: url)

        do {
            let written = try readCiphertext(from: url)
            guard written == archive else { throw ArchiveError.persistenceFailed }
            _ = try open(written, passphrase: passphrase)
        } catch {
            throw ArchiveError.persistenceFailed
        }
    }

    static func read(from url: URL, passphrase: String) throws -> DecodedArchive {
        guard url.pathExtension.lowercased() == fileExtension else {
            throw ArchiveError.invalidFileExtension
        }
        return try open(readCiphertext(from: url), passphrase: passphrase)
    }

    /// Defense-in-depth validation for the provider's explicit replace boundary.
    /// The archive opener already calls the same validation before it returns.
    static func validateForRestore(_ records: [AgentMemory]) throws {
        try validate(records: records)
    }

    private static func decodeAndValidateEnvelope(_ data: Data) throws -> Envelope {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ArchiveError.invalidEnvelope
        }
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == [
                "magic", "formatVersion", "kdf", "iterations", "salt", "ciphertext"
              ]
        else { throw ArchiveError.invalidEnvelope }

        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw ArchiveError.invalidEnvelope
        }
        guard envelope.magic == magic,
              envelope.formatVersion == formatVersion,
              envelope.kdf == kdfName
        else { throw ArchiveError.unsupportedFormat }
        guard allowedIterations.contains(envelope.iterations) else {
            throw ArchiveError.invalidIterations
        }
        guard canonicalBase64(envelope.salt),
              Data(base64Encoded: envelope.salt)?.count == 16,
              canonicalBase64(envelope.ciphertext),
              let combined = Data(base64Encoded: envelope.ciphertext),
              combined.count >= 12 + 16,
              combined.count <= maximumPlaintextBytes + 12 + 16
        else { throw ArchiveError.invalidEnvelope }
        return envelope
    }

    private static func validatePayloadJSONSchema(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ArchiveError.invalidPayload
        }
        guard let payload = object as? [String: Any],
              Set(payload.keys) == ["schemaVersion", "exportedAt", "records"],
              let records = payload["records"] as? [Any],
              records.count <= maximumRecordCount
        else { throw ArchiveError.invalidPayload }

        let required: Set<String> = [
            "id", "content", "tags", "source", "confidence", "importance", "type",
            "createdAt", "updatedAt", "lastSeenAt", "pinned"
        ]
        let optional: Set<String> = [
            "lastAccessedAt", "lastDecayedAt", "expiresAt", "invalidatedAt",
            "supersededBy", "embedding", "embeddingModel"
        ]
        for value in records {
            guard let record = value as? [String: Any],
                  required.isSubset(of: record.keys),
                  Set(record.keys).isSubset(of: required.union(optional)),
                  !record.values.contains(where: { $0 is NSNull })
            else { throw ArchiveError.invalidPayload }
        }
    }

    private static func validate(records: [AgentMemory]) throws {
        guard records.count <= maximumRecordCount else {
            throw ArchiveError.invalidPayload
        }
        var ids = Set<UUID>()
        ids.reserveCapacity(records.count)
        for memory in records {
            guard ids.insert(memory.id).inserted else {
                throw ArchiveError.duplicateRecordID
            }
            try validate(memory: memory)
        }
        for memory in records {
            if let supersededBy = memory.supersededBy {
                // The replacement may later have been explicitly hard-deleted,
                // leaving a legitimate historical pointer. Require the semantic
                // invariant, but preserve such faithful dangling history.
                guard memory.invalidatedAt != nil, supersededBy != memory.id else {
                    throw ArchiveError.invalidRecord
                }
            }
        }
    }

    private static func validate(record: Record) throws {
        guard record.confidence.isFinite,
              (0...1).contains(record.confidence),
              record.importance.isFinite,
              (0...1).contains(record.importance),
              validString(record.content, minimum: 1, maximumUTF8Bytes: 1_048_576),
              validString(record.source, minimum: 1, maximumUTF8Bytes: 4_096),
              record.tags.count <= 256,
              record.tags.allSatisfy({
                  validString($0, minimum: 1, maximumUTF8Bytes: 1_024)
              }),
              validDates(
                  record.createdAt, record.updatedAt, record.lastSeenAt,
                  record.lastAccessedAt, record.lastDecayedAt, record.expiresAt,
                  record.invalidatedAt
              ),
              record.supersededBy != record.id
        else { throw ArchiveError.invalidRecord }
    }

    private static func validate(memory: AgentMemory) throws {
        guard memory.confidence.isFinite,
              (0...1).contains(memory.confidence),
              memory.importance.isFinite,
              (0...1).contains(memory.importance),
              validString(memory.content, minimum: 1, maximumUTF8Bytes: 1_048_576),
              validString(memory.source, minimum: 1, maximumUTF8Bytes: 4_096),
              memory.tags.count <= 256,
              memory.tags.allSatisfy({
                  validString($0, minimum: 1, maximumUTF8Bytes: 1_024)
              }),
              validDates(
                  memory.createdAt, memory.updatedAt, memory.lastSeenAt,
                  memory.lastAccessedAt, memory.lastDecayedAt, memory.expiresAt,
                  memory.invalidatedAt
              ),
              memory.supersededBy != memory.id
        else { throw ArchiveError.invalidRecord }

        if let vector = memory.embedding {
            guard vector.count == EmbeddingService.dimension,
                  vector.allSatisfy(\.isFinite),
                  memory.embeddingModel.map({
                      validString($0, minimum: 1, maximumUTF8Bytes: 1_024)
                  }) == true
            else { throw ArchiveError.invalidRecord }
        } else if memory.embeddingModel != nil {
            throw ArchiveError.invalidRecord
        }
    }

    private static func validatePassphrase(_ passphrase: String) throws {
        guard !passphrase.isEmpty else { throw ArchiveError.emptyPassphrase }
        guard passphrase.count >= 8 else { throw ArchiveError.weakPassphrase }
        guard passphrase.utf8.count <= 4_096 else {
            throw ArchiveError.passphraseTooLong
        }
    }

    private static func validString(
        _ value: String,
        minimum: Int,
        maximumUTF8Bytes: Int
    ) -> Bool {
        let count = value.utf8.count
        return count >= minimum && count <= maximumUTF8Bytes
    }

    private static func validDates(_ dates: Date?...) -> Bool {
        dates.allSatisfy { $0?.timeIntervalSince1970.isFinite ?? true }
    }

    private static func canonicalBase64(_ value: String) -> Bool {
        guard let data = Data(base64Encoded: value) else { return false }
        return data.base64EncodedString() == value
    }

    static func derivedKey(
        passphrase: String,
        salt: Data,
        iterations: Int
    ) throws -> SymmetricKey {
        guard allowedIterations.contains(iterations), salt.count == 16 else {
            throw ArchiveError.invalidIterations
        }
        // 32-byte output equals one HMAC-SHA256 block, so PBKDF2 needs only
        // INT_32_BE(1). Pure CryptoKit keeps this portable across Apple targets.
        let passwordKey = SymmetricKey(data: Data(passphrase.utf8))
        var block = salt
        block.append(contentsOf: [0, 0, 0, 1])
        var u = Data(HMAC<SHA256>.authenticationCode(for: block, using: passwordKey))
        var result = u
        if iterations > 1 {
            for _ in 1..<iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
                for index in result.indices {
                    result[index] ^= u[index]
                }
            }
        }
        return SymmetricKey(data: result)
    }

    private static func readCiphertext(from url: URL) throws -> Data {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= maximumArchiveBytes
        else { throw ArchiveError.invalidEnvelope }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func writeCiphertextDurably(_ archive: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let directoryValues = try directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard directoryValues.isDirectory == true,
              directoryValues.isSymbolicLink != true
        else { throw ArchiveError.persistenceFailed }

        if fileManager.fileExists(atPath: url.path) {
            let targetValues = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard targetValues.isRegularFile == true, targetValues.isSymbolicLink != true else {
                throw ArchiveError.persistenceFailed
            }
        }

        let temporaryURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: archive,
            attributes: [.posixPermissions: 0o600]
        ) else { throw ArchiveError.persistenceFailed }

        var shouldRemoveTemporary = true
        defer {
            if shouldRemoveTemporary {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw ArchiveError.persistenceFailed
        }

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(
                url,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
        shouldRemoveTemporary = false
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        #if canImport(Darwin)
        let directoryDescriptor = Darwin.open(directory.path, O_RDONLY)
        guard directoryDescriptor >= 0 else { throw ArchiveError.persistenceFailed }
        defer { Darwin.close(directoryDescriptor) }
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw ArchiveError.persistenceFailed
        }
        #endif
    }
}
