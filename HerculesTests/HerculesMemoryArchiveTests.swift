import CryptoKit
import XCTest
@testable import Hercules

final class HerculesMemoryArchiveTests: XCTestCase {
    private let passphrase = "correct horse battery"
    private let iterations = HerculesMemoryArchive.allowedIterations.lowerBound
    private let timestamp = Date(timeIntervalSince1970: 1_750_000_000.123_456)

    func testRoundTripPreservesActiveAndInvalidatedHistory() throws {
        let replacementID = UUID()
        let invalidated = AgentMemory(
            content: "Hedefi 80 kg olmak.",
            tags: ["goal", "history"],
            source: "llm-add",
            confidence: 0.88,
            importance: 0.91,
            type: .goal,
            createdAt: timestamp.addingTimeInterval(-3_600),
            updatedAt: timestamp,
            lastSeenAt: timestamp.addingTimeInterval(-1_800),
            lastAccessedAt: timestamp.addingTimeInterval(-600),
            lastDecayedAt: timestamp.addingTimeInterval(-300),
            expiresAt: timestamp.addingTimeInterval(86_400),
            pinned: false,
            invalidatedAt: timestamp,
            supersededBy: replacementID
        )
        let replacement = AgentMemory(
            id: replacementID,
            content: "Hedefi 85 kg olmak.",
            tags: ["goal"],
            source: "llm-add",
            confidence: 0.93,
            importance: 0.96,
            type: .goal,
            createdAt: timestamp,
            updatedAt: timestamp,
            lastSeenAt: timestamp,
            pinned: true
        )

        let data = try HerculesMemoryArchive.seal(
            records: [invalidated, replacement],
            passphrase: passphrase,
            iterations: iterations,
            exportedAt: timestamp
        )
        let decoded = try HerculesMemoryArchive.open(data, passphrase: passphrase)

        XCTAssertEqual(decoded.exportedAt, timestamp)
        XCTAssertEqual(decoded.records, [invalidated, replacement])
        XCTAssertFalse(decoded.records[0].isActive)
        XCTAssertEqual(decoded.records[0].supersededBy, replacement.id)
    }

    func testEnvelopeUsesExactV1ContractAndFreshSalt() throws {
        let first = try HerculesMemoryArchive.seal(
            records: [memory()],
            passphrase: passphrase,
            iterations: iterations,
            exportedAt: timestamp
        )
        let second = try HerculesMemoryArchive.seal(
            records: [memory()],
            passphrase: passphrase,
            iterations: iterations,
            exportedAt: timestamp
        )
        let firstJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: first) as? [String: Any]
        )
        let secondJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: second) as? [String: Any]
        )

        XCTAssertEqual(Set(firstJSON.keys), [
            "magic", "formatVersion", "kdf", "iterations", "salt", "ciphertext"
        ])
        XCTAssertEqual(firstJSON["magic"] as? String, "HERCULESMEMORY")
        XCTAssertEqual(firstJSON["formatVersion"] as? Int, 1)
        XCTAssertEqual(firstJSON["kdf"] as? String, "PBKDF2-SHA256")
        XCTAssertEqual(firstJSON["iterations"] as? Int, iterations)
        XCTAssertEqual(
            Data(base64Encoded: try XCTUnwrap(firstJSON["salt"] as? String))?.count,
            16
        )
        XCTAssertNotEqual(firstJSON["salt"] as? String, secondJSON["salt"] as? String)
        XCTAssertNotEqual(firstJSON["ciphertext"] as? String, secondJSON["ciphertext"] as? String)
        XCTAssertFalse(String(decoding: first, as: UTF8.self).contains(memory().content))
    }

    func testWrongPassphraseAndTamperFailClosed() throws {
        let archive = try HerculesMemoryArchive.seal(
            records: [memory()],
            passphrase: passphrase,
            iterations: iterations
        )
        XCTAssertThrowsError(
            try HerculesMemoryArchive.open(archive, passphrase: "incorrect passphrase")
        ) { error in
            XCTAssertEqual(
                error as? HerculesMemoryArchive.ArchiveError,
                .authenticationFailed
            )
        }

        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: archive) as? [String: Any]
        )
        var ciphertext = try XCTUnwrap(
            Data(base64Encoded: try XCTUnwrap(envelope["ciphertext"] as? String))
        )
        ciphertext[ciphertext.index(before: ciphertext.endIndex)] ^= 0x01
        envelope["ciphertext"] = ciphertext.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: envelope)
        XCTAssertThrowsError(
            try HerculesMemoryArchive.open(tampered, passphrase: passphrase)
        )
    }

    func testEnvelopeRejectsUnknownFieldsAndUnsafeIterationsBeforeKDF() throws {
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try HerculesMemoryArchive.seal(
                records: [memory()],
                passphrase: passphrase,
                iterations: iterations
            )) as? [String: Any]
        )
        envelope["unexpected"] = true
        XCTAssertThrowsError(
            try HerculesMemoryArchive.open(
                try JSONSerialization.data(withJSONObject: envelope),
                passphrase: passphrase
            )
        ) { error in
            XCTAssertEqual(error as? HerculesMemoryArchive.ArchiveError, .invalidEnvelope)
        }

        envelope.removeValue(forKey: "unexpected")
        envelope["iterations"] = HerculesMemoryArchive.allowedIterations.upperBound + 1
        XCTAssertThrowsError(
            try HerculesMemoryArchive.open(
                try JSONSerialization.data(withJSONObject: envelope),
                passphrase: passphrase
            )
        ) { error in
            XCTAssertEqual(error as? HerculesMemoryArchive.ArchiveError, .invalidIterations)
        }
    }

    func testAuthenticatedPayloadWithInvalidValueIsRejected() throws {
        let record = rawRecord()
        var invalidConfidence = record
        invalidConfidence["confidence"] = 1.01
        let archive = try authenticatedArchive(records: [invalidConfidence])

        XCTAssertThrowsError(
            try HerculesMemoryArchive.open(archive, passphrase: passphrase)
        ) { error in
            XCTAssertEqual(error as? HerculesMemoryArchive.ArchiveError, .invalidRecord)
        }
    }

    func testDuplicateIDsAndActiveSupersessionAreRejected() throws {
        let duplicate = memory()
        XCTAssertThrowsError(
            try HerculesMemoryArchive.seal(
                records: [duplicate, duplicate],
                passphrase: passphrase,
                iterations: iterations
            )
        ) { error in
            XCTAssertEqual(error as? HerculesMemoryArchive.ArchiveError, .duplicateRecordID)
        }

        let inconsistent = AgentMemory(
            content: "Eski hedef.",
            tags: [],
            source: "test",
            confidence: 0.8,
            supersededBy: UUID()
        )
        XCTAssertThrowsError(
            try HerculesMemoryArchive.seal(
                records: [inconsistent],
                passphrase: passphrase,
                iterations: iterations
            )
        ) { error in
            XCTAssertEqual(error as? HerculesMemoryArchive.ArchiveError, .invalidRecord)
        }
    }

    func testPassphraseMustHaveAtLeastEightCharacters() {
        XCTAssertThrowsError(
            try HerculesMemoryArchive.seal(
                records: [memory()],
                passphrase: "1234567",
                iterations: iterations
            )
        ) { error in
            XCTAssertEqual(error as? HerculesMemoryArchive.ArchiveError, .weakPassphrase)
        }
    }

    @MainActor
    func testProviderRejectsInvalidRestoreBeforeGenerationInvalidation() async {
        let provider = LocalMemoryProvider.shared
        let generation = provider.automaticWriteGeneration
        let duplicate = memory()

        do {
            _ = try await provider.replaceAllMemoriesDurably(
                with: [duplicate, duplicate]
            )
            XCTFail("Duplicate restore should fail before provider mutation.")
        } catch {
            XCTAssertEqual(
                error as? HerculesMemoryArchive.ArchiveError,
                .duplicateRecordID
            )
        }
        XCTAssertEqual(provider.automaticWriteGeneration, generation)
    }

    func testDurableFileContainsOnlyCiphertextAndCanBeVerified() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HerculesMemoryArchiveTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("memory.herculesmemory")
        let original = memory()

        try HerculesMemoryArchive.write(
            records: [original],
            passphrase: passphrase,
            to: url,
            iterations: iterations,
            exportedAt: timestamp
        )

        let raw = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains(original.content))
        XCTAssertEqual(
            try HerculesMemoryArchive.read(from: url, passphrase: passphrase).records,
            [original]
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    private func memory() -> AgentMemory {
        AgentMemory(
            content: "Kahveyi şekersiz içiyor.",
            tags: ["preference"],
            source: "manual",
            confidence: 1,
            importance: 0.8,
            type: .preference,
            createdAt: timestamp,
            updatedAt: timestamp,
            lastSeenAt: timestamp,
            pinned: true
        )
    }

    private func rawRecord() -> [String: Any] {
        [
            "id": UUID().uuidString,
            "content": "Kahveyi şekersiz içiyor.",
            "tags": ["preference"],
            "source": "manual",
            "confidence": 1.0,
            "importance": 0.8,
            "type": "preference",
            "createdAt": 1_750_000_000.0,
            "updatedAt": 1_750_000_000.0,
            "lastSeenAt": 1_750_000_000.0,
            "pinned": true
        ]
    }

    private func authenticatedArchive(records: [[String: Any]]) throws -> Data {
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "exportedAt": 1_750_000_000.0,
            "records": records
        ]
        let plaintext = try JSONSerialization.data(withJSONObject: payload)
        let salt = Data((0..<16).map(UInt8.init))
        let key = try HerculesMemoryArchive.derivedKey(
            passphrase: passphrase,
            salt: salt,
            iterations: iterations
        )
        let box = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: Data(HerculesMemoryArchive.archiveAAD.utf8)
        )
        let envelope: [String: Any] = [
            "magic": HerculesMemoryArchive.magic,
            "formatVersion": HerculesMemoryArchive.formatVersion,
            "kdf": HerculesMemoryArchive.kdfName,
            "iterations": iterations,
            "salt": salt.base64EncodedString(),
            "ciphertext": try XCTUnwrap(box.combined).base64EncodedString()
        ]
        return try JSONSerialization.data(withJSONObject: envelope)
    }
}
